import SwiftData
import XCTest
@testable import MyWorkingHoursApp

private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

@MainActor
final class MyWorkingHoursAppTests: XCTestCase {
    func testAppSettingsDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.isNotchDisplayEnabled)
        XCTAssertFalse(settings.isMenuBarTimerDisplayEnabled)
    }

    func testAppSettingsPersistsValues() {
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let settings = AppSettings(defaults: defaults)

        settings.isNotchDisplayEnabled = false
        settings.isMenuBarTimerDisplayEnabled = true

        let restoredSettings = AppSettings(defaults: defaults)
        XCTAssertFalse(restoredSettings.isNotchDisplayEnabled)
        XCTAssertTrue(restoredSettings.isMenuBarTimerDisplayEnabled)
    }

    private func makeEngine(clock: TestClock) -> (PersistenceStore, TimerEngine) {
        let store = PersistenceStore(inMemory: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let stateStore = TimerStateStore(defaults: defaults, key: "TestTimerState")
        let engine = TimerEngine(
            context: store.modelContainer.mainContext,
            persistenceStore: store,
            aggregationService: TimeAggregationService(calendar: Calendar(identifier: .gregorian)),
            stateStore: stateStore,
            nowProvider: { clock.now }
        )
        return (store, engine)
    }

    func testStartPauseResumeStopTransitions() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, engine) = makeEngine(clock: clock)

        let task = engine.createTask(named: "深度工作")
        XCTAssertEqual(engine.primaryTask?.id, task.id)
        XCTAssertTrue(engine.isTaskPaused(task))

        engine.start(task: task)
        XCTAssertTrue(engine.isTaskRunning(task))

        clock.now = clock.now.addingTimeInterval(120)
        engine.refreshSnapshot()
        XCTAssertEqual(engine.primarySessionDuration, 120, accuracy: 0.1)

        engine.pause(task: task)
        XCTAssertTrue(engine.isTaskPaused(task))
        XCTAssertNil(engine.primaryRunningEntry)

        var entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.endAt)

        clock.now = clock.now.addingTimeInterval(60)
        engine.start(task: task)
        XCTAssertTrue(engine.isTaskRunning(task))

        entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)

        engine.stopAll()
        XCTAssertFalse(engine.isTaskRunning(task))
        XCTAssertNil(engine.primaryTask)
    }

    func testTodayTotalSplitsAcrossMidnight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 9))!
        let clock = TestClock(selectedDay)
        let (store, engine) = makeEngine(clock: clock)

        let task = engine.createTask(named: "跨午夜任务")
        let start = calendar.date(byAdding: .minute, value: -30, to: calendar.startOfDay(for: selectedDay))!
        let end = calendar.date(byAdding: .minute, value: 30, to: calendar.startOfDay(for: selectedDay))!
        let entry = TimeEntry(task: task, startAt: start, endAt: end, source: .manual, createdAt: start)
        store.modelContainer.mainContext.insert(entry)
        store.save(store.modelContainer.mainContext)

        engine.refreshSnapshot()

        XCTAssertEqual(engine.todayTotalDuration, 1_800, accuracy: 0.1)
    }

    func testStopAllKeepsOnlyClosedEntries() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_100_000))
        let (store, engine) = makeEngine(clock: clock)

        let firstTask = engine.createTask(named: "任务 A")
        let secondTask = engine.createTask(named: "任务 B")

        engine.start(task: firstTask)
        clock.now = clock.now.addingTimeInterval(600)
        engine.start(task: secondTask)

        XCTAssertEqual(engine.runningCount, 2)

        engine.stopAll()

        let entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.filter { $0.endAt == nil }.count, 0)
    }

    // MARK: - Parallel mode tests

    func testParallelStartAllowsMultipleOpenEntries() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        clock.now = clock.now.addingTimeInterval(30)
        engine.start(task: taskB)

        // Both should be running
        XCTAssertTrue(engine.isTaskRunning(taskA))
        XCTAssertTrue(engine.isTaskRunning(taskB))
        XCTAssertEqual(engine.runningCount, 2)

        // Two open entries
        let openEntries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
            .filter { $0.endAt == nil }
        XCTAssertEqual(openEntries.count, 2)
    }

    func testPauseOneDoesNotAffectAnother() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.start(task: taskB)

        clock.now = clock.now.addingTimeInterval(300)
        engine.pause(task: taskA)

        XCTAssertTrue(engine.isTaskPaused(taskA))
        XCTAssertFalse(engine.isTaskRunning(taskA))
        XCTAssertTrue(engine.isTaskRunning(taskB))
        XCTAssertEqual(engine.runningCount, 1)
        XCTAssertEqual(engine.pausedCount, 1)
    }

    func testStopRemovesFromWorkbench() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.start(task: taskB)

        clock.now = clock.now.addingTimeInterval(300)
        engine.stop(task: taskA)

        // A is neither running nor paused
        XCTAssertFalse(engine.isTaskRunning(taskA))
        XCTAssertFalse(engine.isTaskPaused(taskA))
        // B is still running
        XCTAssertTrue(engine.isTaskRunning(taskB))
        XCTAssertEqual(engine.runningCount, 1)
        XCTAssertEqual(engine.pausedCount, 0)
    }

    func testPausedVsStoppedPersistence() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")
        let taskC = engine.createTask(named: "任务 C")

        engine.start(task: taskA)
        engine.start(task: taskB)
        engine.start(task: taskC)

        clock.now = clock.now.addingTimeInterval(300)
        engine.pause(task: taskA) // paused
        engine.stop(task: taskB)  // stopped

        // Simulate app restart: create new engine with same store
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let stateStore = TimerStateStore(defaults: defaults, key: "TestTimerState")
        stateStore.save(engine.timerState)

        let engine2 = TimerEngine(
            context: store.modelContainer.mainContext,
            persistenceStore: store,
            aggregationService: TimeAggregationService(calendar: Calendar(identifier: .gregorian)),
            stateStore: stateStore,
            nowProvider: { clock.now }
        )

        // A should still be paused
        XCTAssertTrue(engine2.isTaskPaused(taskA))
        XCTAssertFalse(engine2.isTaskRunning(taskA))
        // B should be gone (stopped)
        XCTAssertFalse(engine2.isTaskPaused(taskB))
        XCTAssertFalse(engine2.isTaskRunning(taskB))
        // C should still be running (has open entry)
        XCTAssertTrue(engine2.isTaskRunning(taskC))
    }

    func testPrimaryRotatesOnStop() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.setPrimaryTask(taskA)
        engine.start(task: taskB)

        XCTAssertEqual(engine.primaryTask?.id, taskA.id)

        engine.stop(task: taskA)

        // Primary should rotate to the other running task
        XCTAssertEqual(engine.primaryTask?.id, taskB.id)
    }

    func testPrimaryRotatesOnPauseWhenOthersRunning() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.setPrimaryTask(taskA)
        engine.start(task: taskB)

        engine.pause(task: taskA)

        // B is still running, so primary should rotate to B
        XCTAssertEqual(engine.primaryTask?.id, taskB.id)
    }

    func testPrimaryStaysPausedWhenNoneRunning() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")

        engine.start(task: taskA)
        XCTAssertEqual(engine.primaryTask?.id, taskA.id)

        engine.pause(task: taskA)

        // No other running tasks, so primary stays as the paused task
        XCTAssertEqual(engine.primaryTask?.id, taskA.id)
    }

    func testPrimaryClearsOnStopWhenNoneRunning() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        engine.start(task: taskA)
        engine.stop(task: taskA)

        XCTAssertNil(engine.primaryTask)
    }

    func testTotalDurationVsWallClockDuration() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        // Start both at the same time
        engine.start(task: taskA)
        engine.start(task: taskB)

        // Advance 1 hour
        clock.now = clock.now.addingTimeInterval(3_600)
        engine.refreshSnapshot()

        // Total (cumulative) = 2h (each task ran 1h)
        XCTAssertEqual(engine.todayTotalDuration, 7_200, accuracy: 1)
        // Wall clock = 1h (overlapping, only count once)
        XCTAssertEqual(engine.todayWallClockDuration, 3_600, accuracy: 1)
    }

    func testWallClockWithPartialOverlap() throws {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 9))!
        let clock = TestClock(baseDate)
        let (store, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        // A: 09:00 - 11:00 (2h)
        let entryA = TimeEntry(task: taskA, startAt: baseDate,
                               endAt: calendar.date(byAdding: .hour, value: 2, to: baseDate)!,
                               source: .manual, createdAt: baseDate)
        // B: 10:00 - 12:00 (2h, overlaps A by 1h)
        let entryB = TimeEntry(task: taskB,
                               startAt: calendar.date(byAdding: .hour, value: 1, to: baseDate)!,
                               endAt: calendar.date(byAdding: .hour, value: 3, to: baseDate)!,
                               source: .manual, createdAt: baseDate)
        store.modelContainer.mainContext.insert(entryA)
        store.modelContainer.mainContext.insert(entryB)
        store.save(store.modelContainer.mainContext)

        clock.now = calendar.date(byAdding: .hour, value: 4, to: baseDate)!
        engine.refreshSnapshot()

        // Total = 2h + 2h = 4h
        XCTAssertEqual(engine.todayTotalDuration, 14_400, accuracy: 1)
        // Wall clock = 09:00 - 12:00 = 3h
        XCTAssertEqual(engine.todayWallClockDuration, 10_800, accuracy: 1)
    }

    func testPauseAllAndStopAll() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.start(task: taskB)
        XCTAssertEqual(engine.runningCount, 2)

        engine.pauseAll()
        XCTAssertEqual(engine.runningCount, 0)
        XCTAssertEqual(engine.pausedCount, 2)
        XCTAssertTrue(engine.isTaskPaused(taskA))
        XCTAssertTrue(engine.isTaskPaused(taskB))

        // Resume one
        engine.start(task: taskA)
        XCTAssertEqual(engine.runningCount, 1)
        XCTAssertEqual(engine.pausedCount, 1)

        engine.stopAll()
        XCTAssertEqual(engine.runningCount, 0)
        XCTAssertEqual(engine.pausedCount, 0)
        XCTAssertNil(engine.primaryTask)
    }

    func testStartFromPausedRemovesFromPausedSet() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")

        engine.start(task: taskA)
        engine.pause(task: taskA)
        XCTAssertTrue(engine.isTaskPaused(taskA))

        engine.start(task: taskA)
        XCTAssertTrue(engine.isTaskRunning(taskA))
        XCTAssertFalse(engine.isTaskPaused(taskA))
    }

    func testManualEditRecomputesAggregates() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_200_000))
        let (store, engine) = makeEngine(clock: clock)

        let task = engine.createTask(named: "补录任务")
        let entry = TimeEntry(
            task: task,
            startAt: clock.now,
            endAt: clock.now.addingTimeInterval(3_600),
            source: .manual,
            createdAt: clock.now
        )
        store.modelContainer.mainContext.insert(entry)
        store.save(store.modelContainer.mainContext)

        engine.notifyDataChanged()
        XCTAssertEqual(engine.todayTotalDuration, 3_600, accuracy: 0.1)

        entry.endAt = clock.now.addingTimeInterval(7_200)
        store.save(store.modelContainer.mainContext)
        engine.notifyDataChanged()

        XCTAssertEqual(engine.todayTotalDuration, 7_200, accuracy: 0.1)
        let entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(engine.aggregationService.totalDuration(for: task, entries: entries, now: clock.now), 7_200, accuracy: 0.1)
    }

    // MARK: - Edge case tests (Phase 4)

    func testDeletePausedTaskCleansUpState() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, engine) = makeEngine(clock: clock)

        let task = engine.createTask(named: "将被删除")
        engine.start(task: task)
        engine.pause(task: task)
        XCTAssertTrue(engine.isTaskPaused(task))

        // Simulate deletion outside of engine
        store.modelContainer.mainContext.delete(task)
        store.save(store.modelContainer.mainContext)

        // After refresh, repair should clean up the dangling paused ID
        engine.notifyDataChanged()
        XCTAssertEqual(engine.pausedCount, 0)
        XCTAssertNil(engine.primaryTask)
    }

    func testDeletePrimaryTaskRotatesOrClears() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "主任务")
        let taskB = engine.createTask(named: "副任务")

        engine.start(task: taskA)
        engine.start(task: taskB)
        engine.setPrimaryTask(taskA)

        // Delete primary task externally
        engine.stop(task: taskA)
        store.modelContainer.mainContext.delete(taskA)
        store.save(store.modelContainer.mainContext)

        engine.notifyDataChanged()

        // Should rotate to B
        XCTAssertEqual(engine.primaryTask?.id, taskB.id)
    }

    func testCrashRecoveryMultipleOpenEntries() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (store, _) = makeEngine(clock: clock)
        let ctx = store.modelContainer.mainContext

        // Simulate crash: manually insert 3 open entries for different tasks
        let taskA = WorkTask(title: "A", createdAt: clock.now, updatedAt: clock.now)
        let taskB = WorkTask(title: "B", createdAt: clock.now, updatedAt: clock.now)
        let taskC = WorkTask(title: "C", createdAt: clock.now, updatedAt: clock.now)
        ctx.insert(taskA)
        ctx.insert(taskB)
        ctx.insert(taskC)

        let entryA = TimeEntry(task: taskA, startAt: clock.now, endAt: nil, source: .automatic, createdAt: clock.now)
        let entryB = TimeEntry(task: taskB, startAt: clock.now.addingTimeInterval(10), endAt: nil, source: .automatic, createdAt: clock.now)
        let entryC = TimeEntry(task: taskC, startAt: clock.now.addingTimeInterval(20), endAt: nil, source: .automatic, createdAt: clock.now)
        ctx.insert(entryA)
        ctx.insert(entryB)
        ctx.insert(entryC)
        store.save(ctx)

        // Create a fresh engine (simulating restart)
        clock.now = clock.now.addingTimeInterval(600)
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let stateStore = TimerStateStore(defaults: defaults, key: "CrashTest")
        let engine = TimerEngine(
            context: ctx,
            persistenceStore: store,
            aggregationService: TimeAggregationService(calendar: Calendar(identifier: .gregorian)),
            stateStore: stateStore,
            nowProvider: { clock.now }
        )

        // All 3 should be running — no auto-close
        XCTAssertEqual(engine.runningCount, 3)
        let openEntries = try ctx.fetch(FetchDescriptor<TimeEntry>()).filter { $0.endAt == nil }
        XCTAssertEqual(openEntries.count, 3)
    }

    func testMidnightRolloverRefreshesToday() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 23, minute: 50))!
        let clock = TestClock(day1)
        let (_, engine) = makeEngine(clock: clock)

        let task = engine.createTask(named: "跨天任务")

        // Start at 23:50
        engine.start(task: task)

        // Advance to 00:10 next day
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 0, minute: 10))!
        engine.refreshSnapshot()

        // Wall clock for day 16 should be 10 minutes (00:00 - 00:10)
        XCTAssertEqual(engine.todayWallClockDuration, 600, accuracy: 1)
        // Total duration for day 16 should also be 10 minutes
        XCTAssertEqual(engine.todayTotalDuration, 600, accuracy: 1)
    }

    func testDeleteRunningEntryOnlyAffectsItsTask() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (_, engine) = makeEngine(clock: clock)

        let taskA = engine.createTask(named: "任务 A")
        let taskB = engine.createTask(named: "任务 B")

        engine.start(task: taskA)
        engine.start(task: taskB)
        XCTAssertEqual(engine.runningCount, 2)

        // Stop only A
        engine.stop(task: taskA)

        // B should still be running
        XCTAssertTrue(engine.isTaskRunning(taskB))
        XCTAssertEqual(engine.runningCount, 1)
    }
}
