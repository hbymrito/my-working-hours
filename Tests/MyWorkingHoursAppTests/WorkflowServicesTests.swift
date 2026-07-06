import SwiftData
import XCTest
@testable import MyWorkingHoursApp

@MainActor
final class WorkflowServicesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int = 3, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute, second: second))!
    }

    func testTimelineClipsCrossMidnightAndOpenEntries() {
        let task = WorkTask(title: "任务")
        let crossMidnight = TimeEntry(
            task: task,
            startAt: date(2, hour: 23, minute: 30),
            endAt: date(hour: 0, minute: 30)
        )
        let open = TimeEntry(task: task, startAt: date(hour: 10), endAt: nil)

        let analysis = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [crossMidnight, open],
            now: date(hour: 11)
        )

        XCTAssertEqual(analysis.items.count, 2)
        let clipped = analysis.items.first { $0.entryID == crossMidnight.id }!
        XCTAssertEqual(clipped.start, date(hour: 0))
        XCTAssertEqual(clipped.end, date(hour: 0, minute: 30))
        XCTAssertTrue(clipped.anomalies.contains(.crossesMidnight))

        let openItem = analysis.items.first { $0.entryID == open.id }!
        XCTAssertEqual(openItem.end, date(hour: 11))
    }

    func testTimelineReturnsEmptyAnalysisForDayWithoutEntries() {
        let analysis = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [],
            now: date(hour: 13)
        )

        XCTAssertTrue(analysis.items.isEmpty)
        XCTAssertTrue(analysis.mergeSuggestions.isEmpty)
    }

    func testTimelineAssignsOverlapLanesAndReusesAdjacentLane() {
        let task = WorkTask(title: "任务")
        let first = TimeEntry(task: task, startAt: date(hour: 9), endAt: date(hour: 11))
        let second = TimeEntry(task: task, startAt: date(hour: 9, minute: 30), endAt: date(hour: 10, minute: 30))
        let third = TimeEntry(task: task, startAt: date(hour: 9, minute: 45), endAt: date(hour: 10))
        let adjacent = TimeEntry(task: task, startAt: date(hour: 11), endAt: date(hour: 12))

        let items = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [first, second, third, adjacent],
            now: date(hour: 13)
        ).items

        XCTAssertEqual(Set(items.prefix(3).map(\.laneCount)), [3])
        XCTAssertEqual(Set(items.prefix(3).map(\.laneIndex)), [0, 1, 2])
        XCTAssertEqual(items.first { $0.entryID == adjacent.id }?.laneIndex, 0)
        XCTAssertEqual(items.first { $0.entryID == adjacent.id }?.laneCount, 1)
    }

    func testTimelineMarksAllAnomalyTypes() {
        let task = WorkTask(title: "任务")
        let short = TimeEntry(task: task, startAt: date(hour: 8), endAt: date(hour: 8, second: 30))
        let long = TimeEntry(task: task, startAt: date(hour: 9), endAt: date(hour: 13, minute: 1))
        let overlap = TimeEntry(task: task, startAt: date(hour: 10), endAt: date(hour: 10, minute: 30))
        let cross = TimeEntry(task: task, startAt: date(2, hour: 23), endAt: date(hour: 1))

        let items = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [short, long, overlap, cross],
            now: date(hour: 14)
        ).items

        XCTAssertTrue(items.first { $0.entryID == short.id }!.anomalies.contains(.short))
        XCTAssertTrue(items.first { $0.entryID == long.id }!.anomalies.contains(.long))
        XCTAssertTrue(items.first { $0.entryID == long.id }!.anomalies.contains(.overlapping))
        XCTAssertTrue(items.first { $0.entryID == overlap.id }!.anomalies.contains(.overlapping))
        XCTAssertTrue(items.first { $0.entryID == cross.id }!.anomalies.contains(.crossesMidnight))
    }

    func testMergeSuggestionsRespectTaskStateAndFiveMinuteBoundary() {
        let firstTask = WorkTask(title: "任务 A")
        let secondTask = WorkTask(title: "任务 B")
        let entries = [
            TimeEntry(task: firstTask, startAt: date(hour: 9), endAt: date(hour: 9, minute: 30)),
            TimeEntry(task: firstTask, startAt: date(hour: 9, minute: 35), endAt: date(hour: 10)),
            TimeEntry(task: firstTask, startAt: date(hour: 10, minute: 6), endAt: date(hour: 10, minute: 30)),
            TimeEntry(task: secondTask, startAt: date(hour: 10), endAt: date(hour: 10, minute: 5)),
            TimeEntry(task: firstTask, startAt: date(hour: 11), endAt: nil),
        ]

        let suggestions = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: entries,
            now: date(hour: 12)
        ).mergeSuggestions

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].entryIDs, [entries[0].id, entries[1].id])
        XCTAssertEqual(suggestions[0].includedGapDuration, 5 * 60, accuracy: 0.1)
    }

    func testMergeMutationKeepsFirstEntryAndMarksItManual() throws {
        let store = PersistenceStore(inMemory: true)
        let context = store.modelContainer.mainContext
        let task = WorkTask(title: "任务")
        let first = TimeEntry(task: task, startAt: date(hour: 9), endAt: date(hour: 9, minute: 30))
        let second = TimeEntry(task: task, startAt: date(hour: 9, minute: 32), endAt: date(hour: 10))
        context.insert(task)
        context.insert(first)
        context.insert(second)
        try context.save()

        let suggestion = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [first, second],
            now: date(hour: 12)
        ).mergeSuggestions[0]
        let survivor = try TimeEntryMaintenanceService(modelContext: context).merge(
            suggestion,
            entries: [first, second]
        )

        XCTAssertEqual(survivor.id, first.id)
        XCTAssertEqual(survivor.endAt, date(hour: 10))
        XCTAssertEqual(survivor.source, .manual)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimeEntry>()).count, 1)
    }

    func testMergeCanRefreshTimerEngineAggregate() throws {
        let store = PersistenceStore(inMemory: true)
        let context = store.modelContainer.mainContext
        let task = WorkTask(title: "任务")
        let first = TimeEntry(task: task, startAt: date(hour: 9), endAt: date(hour: 9, minute: 30))
        let second = TimeEntry(task: task, startAt: date(hour: 9, minute: 32), endAt: date(hour: 10))
        context.insert(task)
        context.insert(first)
        context.insert(second)
        try context.save()

        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let engine = TimerEngine(
            context: context,
            persistenceStore: store,
            aggregationService: TimeAggregationService(calendar: calendar),
            stateStore: TimerStateStore(defaults: defaults, key: "MergeRefresh"),
            nowProvider: { self.date(hour: 12) }
        )
        XCTAssertEqual(engine.todayTotalDuration, 58 * 60, accuracy: 0.1)

        let suggestion = TimelineWorkflowService(calendar: calendar).analyze(
            day: date(hour: 12),
            entries: [first, second],
            now: date(hour: 12)
        ).mergeSuggestions[0]
        try TimeEntryMaintenanceService(modelContext: context).merge(suggestion, entries: [first, second])
        engine.notifyDataChanged()

        XCTAssertEqual(engine.todayTotalDuration, 60 * 60, accuracy: 0.1)
    }

    func testArchiveBucketsUseLastEntryAndExcludeActiveTasks() {
        let now = date(hour: 12)
        let stale = WorkTask(title: "过期", createdAt: calendar.date(byAdding: .day, value: -31, to: now)!, updatedAt: now)
        let exactBoundary = WorkTask(title: "边界", createdAt: calendar.date(byAdding: .day, value: -30, to: now)!, updatedAt: now)
        let recent = WorkTask(title: "最近", createdAt: calendar.date(byAdding: .day, value: -60, to: now)!, updatedAt: now)
        let running = WorkTask(title: "运行中", createdAt: calendar.date(byAdding: .day, value: -60, to: now)!, updatedAt: now)
        let archived = WorkTask(title: "已归档", isArchived: true, createdAt: now, updatedAt: now)
        let recentEntry = TimeEntry(
            task: recent,
            startAt: calendar.date(byAdding: .day, value: -1, to: now)!,
            endAt: now
        )

        let buckets = TaskWorkflowService(calendar: calendar).archiveBuckets(
            tasks: [stale, exactBoundary, recent, running, archived],
            entries: [recentEntry],
            activeTaskIDs: [running.id],
            now: now
        )

        XCTAssertEqual(Set(buckets.suggested.map(\.id)), [stale.id, exactBoundary.id])
        XCTAssertEqual(Set(buckets.active.map(\.id)), [recent.id, running.id])
        XCTAssertEqual(buckets.archived.map(\.id), [archived.id])
    }

    func testQuickSearchAndDuplicateMatching() {
        let project = Project(name: "暨南大学附属第一医院")
        let ticketTask = WorkTask(title: "YT02675 体检套餐同步", project: project)
        let archived = WorkTask(title: "YT09999 旧任务", project: project, isArchived: true)
        let service = TaskWorkflowService(calendar: calendar)

        XCTAssertEqual(service.filterQuickTasks([ticketTask, archived], query: "暨南").map(\.id), [ticketTask.id])
        XCTAssertEqual(service.filterQuickTasks([ticketTask, archived], query: "YT-02675").map(\.id), [ticketTask.id])
        XCTAssertTrue(service.filterQuickTasks([ticketTask, archived], query: "旧任务").isEmpty)
        XCTAssertEqual(
            service.duplicateCandidates(for: "YT02675 新标题", tasks: [ticketTask, archived], selectedProjectID: project.id).map(\.id),
            [ticketTask.id]
        )
    }
}
