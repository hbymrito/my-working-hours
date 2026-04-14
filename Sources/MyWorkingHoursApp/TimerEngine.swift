import AppKit
import Foundation
import SwiftData

@MainActor
final class TimerStateStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "MyWorkingHours.TimerState") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> TimerState? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(TimerState.self, from: data)
    }

    func save(_ state: TimerState) {
        guard let encoded = try? JSONEncoder().encode(state) else {
            return
        }

        defaults.set(encoded, forKey: key)
    }
}

@MainActor
final class TimerEngine: ObservableObject {
    enum TimerError: Error {
        case noSelectedTask
    }

    @Published private(set) var timerState: TimerState
    @Published private(set) var activeTask: WorkTask?
    @Published private(set) var activeEntry: TimeEntry?
    @Published private(set) var currentSessionDuration: TimeInterval = 0
    @Published private(set) var todayTotalDuration: TimeInterval = 0
    @Published private(set) var now: Date

    let aggregationService: TimeAggregationService

    private let modelContext: ModelContext
    private let persistenceStore: PersistenceStore
    private let stateStore: TimerStateStore
    private let nowProvider: () -> Date

    private var heartbeat: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        context: ModelContext,
        persistenceStore: PersistenceStore,
        aggregationService: TimeAggregationService,
        stateStore: TimerStateStore = TimerStateStore(),
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        modelContext = context
        self.persistenceStore = persistenceStore
        self.aggregationService = aggregationService
        self.stateStore = stateStore
        self.nowProvider = nowProvider
        let initialNow = nowProvider()
        now = initialNow
        timerState = stateStore.load() ?? .idle(now: initialNow)

        repairStateIfNeeded()
        refreshSnapshot()
    }

    func activate() {
        guard heartbeat == nil else {
            return
        }

        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refreshSnapshot()
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshSnapshot()
                }
            }
        )

        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshSnapshot()
                }
            }
        )
    }

    func startTimer() throws {
        let timestamp = nowProvider()
        guard let task = activeTask ?? fetchTask(id: timerState.activeTaskID) else {
            throw TimerError.noSelectedTask
        }

        if timerState.status == .running {
            return
        }

        let entry = TimeEntry(
            task: task,
            startAt: timestamp,
            endAt: nil,
            source: .automatic,
            createdAt: timestamp
        )

        task.updatedAt = timestamp
        modelContext.insert(entry)

        activeTask = task
        activeEntry = entry
        timerState = TimerState(
            activeTaskID: task.id,
            activeEntryStartAt: timestamp,
            status: .running,
            lastInteractionAt: timestamp
        )

        persistAndRefresh()
    }

    func pauseTimer() {
        guard timerState.status == .running else {
            return
        }

        let timestamp = nowProvider()
        closeActiveEntry(at: timestamp, persist: false)
        timerState.status = .paused
        timerState.activeEntryStartAt = nil
        timerState.lastInteractionAt = timestamp

        persistAndRefresh()
    }

    func stopTimer() {
        let timestamp = nowProvider()
        closeActiveEntry(at: timestamp, persist: false)

        activeTask = nil
        timerState = .idle(now: timestamp)

        persistAndRefresh()
    }

    func selectTask(_ task: WorkTask?) {
        let timestamp = nowProvider()
        activeTask = task
        timerState.activeTaskID = task?.id
        timerState.activeEntryStartAt = nil
        timerState.status = task == nil ? .idle : .paused
        timerState.lastInteractionAt = timestamp

        persistAndRefresh()
    }

    func switchTask(to task: WorkTask) {
        let timestamp = nowProvider()
        closeActiveEntry(at: timestamp, persist: false)

        let entry = TimeEntry(
            task: task,
            startAt: timestamp,
            endAt: nil,
            source: .automatic,
            createdAt: timestamp
        )

        modelContext.insert(entry)
        task.updatedAt = timestamp

        activeTask = task
        activeEntry = entry
        timerState = TimerState(
            activeTaskID: task.id,
            activeEntryStartAt: timestamp,
            status: .running,
            lastInteractionAt: timestamp
        )

        persistAndRefresh()
    }

    @discardableResult
    func createTask(named title: String, project: Project? = nil) -> WorkTask {
        let timestamp = nowProvider()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = WorkTask(
            title: trimmed.isEmpty ? "新任务" : trimmed,
            notes: "",
            project: project,
            isArchived: false,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        modelContext.insert(task)
        persistenceStore.save(modelContext)
        selectTask(task)

        return task
    }

    func refreshSnapshot() {
        now = nowProvider()
        repairStateIfNeeded()

        if let runningEntry = openRunningEntry() {
            activeEntry = runningEntry
            activeTask = runningEntry.task
        } else {
            activeEntry = nil
            activeTask = fetchTask(id: timerState.activeTaskID)
        }

        if let activeEntry, timerState.status == .running {
            currentSessionDuration = max(0, now.timeIntervalSince(activeEntry.startAt))
        } else {
            currentSessionDuration = 0
        }

        todayTotalDuration = aggregationService.totalDuration(on: now, entries: fetchAllEntries(), now: now)
        stateStore.save(timerState)
    }

    private func repairStateIfNeeded() {
        let timestamp = nowProvider()
        let openEntries = fetchOpenEntries().sorted { $0.startAt < $1.startAt }

        if openEntries.count > 1, let newest = openEntries.last {
            for entry in openEntries.dropLast() {
                entry.endAt = max(entry.startAt, newest.startAt)
            }

            persistenceStore.save(modelContext)
        }

        if let runningEntry = openRunningEntry() {
            activeEntry = runningEntry
            activeTask = runningEntry.task
            timerState.activeTaskID = runningEntry.task?.id
            timerState.activeEntryStartAt = runningEntry.startAt
            timerState.status = .running
            timerState.lastInteractionAt = timestamp
            return
        }

        activeEntry = nil
        activeTask = fetchTask(id: timerState.activeTaskID)

        if timerState.status == .running {
            timerState.status = activeTask == nil ? .idle : .paused
            timerState.activeEntryStartAt = nil
        }
    }

    private func closeActiveEntry(at timestamp: Date, persist: Bool) {
        guard let entry = activeEntry ?? openRunningEntry() else {
            activeEntry = nil
            return
        }

        if entry.endAt == nil {
            entry.endAt = max(entry.startAt, timestamp)
        }

        entry.task?.updatedAt = timestamp
        activeEntry = nil

        if persist {
            persistenceStore.save(modelContext)
        }
    }

    private func fetchTask(id: UUID?) -> WorkTask? {
        guard let id else {
            return nil
        }

        let descriptor = FetchDescriptor<WorkTask>(
            predicate: #Predicate<WorkTask> { task in
                task.id == id
            }
        )

        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOpenEntries() -> [TimeEntry] {
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { entry in
                entry.endAt == nil
            },
            sortBy: [SortDescriptor(\.startAt)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func openRunningEntry() -> TimeEntry? {
        fetchOpenEntries().last
    }

    private func fetchAllEntries() -> [TimeEntry] {
        let descriptor = FetchDescriptor<TimeEntry>(
            sortBy: [SortDescriptor(\.startAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func persistAndRefresh() {
        persistenceStore.save(modelContext)
        refreshSnapshot()
    }
}
