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
        XCTAssertEqual(engine.activeTask?.id, task.id)
        XCTAssertEqual(engine.timerState.status, .paused)

        try engine.startTimer()
        XCTAssertEqual(engine.timerState.status, .running)

        clock.now = clock.now.addingTimeInterval(120)
        engine.refreshSnapshot()
        XCTAssertEqual(engine.currentSessionDuration, 120, accuracy: 0.1)

        engine.pauseTimer()
        XCTAssertEqual(engine.timerState.status, .paused)
        XCTAssertNil(engine.activeEntry)

        var entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.endAt)

        clock.now = clock.now.addingTimeInterval(60)
        try engine.startTimer()
        XCTAssertEqual(engine.timerState.status, .running)

        entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)

        engine.stopTimer()
        XCTAssertEqual(engine.timerState.status, .idle)
        XCTAssertNil(engine.activeTask)
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

    func testSwitchTaskKeepsOnlyOneRunningEntry() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_100_000))
        let (store, engine) = makeEngine(clock: clock)

        let firstTask = engine.createTask(named: "任务 A")
        let secondTask = engine.createTask(named: "任务 B")

        engine.selectTask(firstTask)
        try engine.startTimer()

        clock.now = clock.now.addingTimeInterval(600)
        engine.switchTask(to: secondTask)

        let entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.filter { $0.endAt == nil }.count, 1)
        XCTAssertEqual(entries.first(where: { $0.endAt == nil })?.task?.id, secondTask.id)
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

        engine.refreshSnapshot()
        XCTAssertEqual(engine.todayTotalDuration, 3_600, accuracy: 0.1)

        entry.endAt = clock.now.addingTimeInterval(7_200)
        store.save(store.modelContainer.mainContext)
        engine.refreshSnapshot()

        XCTAssertEqual(engine.todayTotalDuration, 7_200, accuracy: 0.1)
        let entries = try store.modelContainer.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(engine.aggregationService.totalDuration(for: task, entries: entries, now: clock.now), 7_200, accuracy: 0.1)
    }
}
