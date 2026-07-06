import AppKit
import Foundation
import SwiftData

@MainActor
final class TimerMetrics: ObservableObject {
    struct Snapshot {
        let now: Date
        let primarySessionDuration: TimeInterval
        let todayTotalDuration: TimeInterval
        let todayWallClockDuration: TimeInterval
    }

    @Published private(set) var snapshot: Snapshot

    var now: Date { snapshot.now }
    var primarySessionDuration: TimeInterval { snapshot.primarySessionDuration }
    var todayTotalDuration: TimeInterval { snapshot.todayTotalDuration }
    var todayWallClockDuration: TimeInterval { snapshot.todayWallClockDuration }

    init(now: Date) {
        snapshot = Snapshot(
            now: now,
            primarySessionDuration: 0,
            todayTotalDuration: 0,
            todayWallClockDuration: 0
        )
    }

    func update(
        now: Date,
        primarySessionDuration: TimeInterval,
        todayTotalDuration: TimeInterval,
        todayWallClockDuration: TimeInterval
    ) {
        snapshot = Snapshot(
            now: now,
            primarySessionDuration: primarySessionDuration,
            todayTotalDuration: todayTotalDuration,
            todayWallClockDuration: todayWallClockDuration
        )
    }
}

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
    // MARK: - Published state

    @Published private(set) var timerState: TimerState
    @Published private(set) var runningEntries: [TimeEntry] = []
    @Published private(set) var runningTasks: [WorkTask] = []
    @Published private(set) var pausedTasks: [WorkTask] = []
    @Published private(set) var primaryTask: WorkTask?
    @Published private(set) var primaryRunningEntry: TimeEntry?
    @Published private(set) var runningCount: Int = 0
    @Published private(set) var pausedCount: Int = 0

    let aggregationService: TimeAggregationService
    let metrics: TimerMetrics

    var primarySessionDuration: TimeInterval { metrics.primarySessionDuration }
    var todayTotalDuration: TimeInterval { metrics.todayTotalDuration }
    var todayWallClockDuration: TimeInterval { metrics.todayWallClockDuration }
    var now: Date { metrics.now }

    private let modelContext: ModelContext
    private let persistenceStore: PersistenceStore
    private let stateStore: TimerStateStore
    let nowProvider: () -> Date

    private var heartbeat: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Cached entries — only re-fetched when `entriesDirty` is true.
    private var cachedOpenEntries: [TimeEntry] = []
    private var cachedAllEntries: [TimeEntry] = []
    private var cachedTodayEntries: [TimeEntry] = []
    private var entriesDirty = true
    /// Track the last day we refreshed for midnight rollover detection.
    private var lastRefreshDay: Int = -1

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
        metrics = TimerMetrics(now: initialNow)
        timerState = stateStore.load() ?? .idle(now: initialNow)
        lastRefreshDay = aggregationService.calendar.component(.day, from: initialNow)

        // Force full fetch on first refresh
        entriesDirty = true
        refreshSnapshot()
    }

    func activate() {
        guard heartbeat == nil else {
            return
        }

        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.tickRefresh()
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

    // MARK: - Parallel task API

    func start(task: WorkTask) {
        let timestamp = nowProvider()

        // If already running, no-op
        guard !isTaskRunning(task) else { return }

        // Remove from paused if it was paused
        timerState.pausedTaskIDs.remove(task.id)

        let entry = TimeEntry(
            task: task,
            startAt: timestamp,
            endAt: nil,
            source: .automatic,
            createdAt: timestamp
        )

        task.updatedAt = timestamp
        modelContext.insert(entry)

        // Promote to primary if no primary or resuming from paused
        if timerState.primaryTaskID == nil || timerState.primaryTaskID == task.id {
            timerState.primaryTaskID = task.id
        }

        timerState.lastInteractionAt = timestamp
        let canUpdateCacheIncrementally = !entriesDirty
        persistenceStore.save(modelContext)

        if canUpdateCacheIncrementally {
            cachedOpenEntries.append(entry)
            cachedOpenEntries.sort { $0.startAt < $1.startAt }
            cachedAllEntries.append(entry)
            cachedAllEntries.sort { $0.startAt > $1.startAt }
            cachedTodayEntries.append(entry)
            publishSnapshot(at: timestamp)
        } else {
            invalidateCache()
            refreshSnapshot()
        }
    }

    func pause(task: WorkTask) {
        let timestamp = nowProvider()

        // Close all open entries for this task
        closeEntries(for: task, at: timestamp)

        // Add to paused set
        timerState.pausedTaskIDs.insert(task.id)
        timerState.lastInteractionAt = timestamp

        // Primary rotation: if pausing the primary, try to find another running task
        if timerState.primaryTaskID == task.id {
            rotatePrimaryAfterPause(task: task)
        }

        persistAndRefresh()
    }

    func stop(task: WorkTask) {
        let timestamp = nowProvider()

        // Close all open entries for this task
        closeEntries(for: task, at: timestamp)

        // Remove from paused set entirely
        timerState.pausedTaskIDs.remove(task.id)
        timerState.lastInteractionAt = timestamp

        // Primary rotation: if stopping the primary, find another running task
        if timerState.primaryTaskID == task.id {
            rotatePrimaryAfterStop()
        }

        persistAndRefresh()
    }

    func pauseAll() {
        let timestamp = nowProvider()
        let openEntries = fetchOpenEntries()

        for entry in openEntries {
            if entry.endAt == nil {
                entry.endAt = max(entry.startAt, timestamp)
            }
            if let task = entry.task {
                timerState.pausedTaskIDs.insert(task.id)
                task.updatedAt = timestamp
            }
        }

        timerState.lastInteractionAt = timestamp
        // Keep primaryTaskID as-is (it's now paused, but still primary since all are paused)
        persistAndRefresh()
    }

    func stopAll() {
        let timestamp = nowProvider()
        let openEntries = fetchOpenEntries()

        for entry in openEntries {
            if entry.endAt == nil {
                entry.endAt = max(entry.startAt, timestamp)
            }
            entry.task?.updatedAt = timestamp
        }

        timerState.pausedTaskIDs.removeAll()
        timerState.primaryTaskID = nil
        timerState.lastInteractionAt = timestamp

        persistAndRefresh()
    }

    func setPrimaryTask(_ task: WorkTask) {
        timerState.primaryTaskID = task.id
        timerState.lastInteractionAt = nowProvider()
        persistAndRefresh()
    }

    func isTaskRunning(_ task: WorkTask) -> Bool {
        runningTasks.contains { $0.id == task.id }
    }

    func isTaskPaused(_ task: WorkTask) -> Bool {
        timerState.pausedTaskIDs.contains(task.id)
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

        // Set as primary and add to paused (ready to start)
        var newState = timerState
        newState.primaryTaskID = task.id
        newState.pausedTaskIDs.insert(task.id)
        newState.lastInteractionAt = timestamp
        newState.status = runningCount > 0 ? .running : .paused
        timerState = newState

        primaryTask = task
        primaryRunningEntry = nil
        pausedTasks.append(task)
        pausedCount = pausedTasks.count

        persistenceStore.save(modelContext)
        stateStore.save(timerState)

        return task
    }

    // MARK: - Snapshot refresh

    /// Force a full re-fetch and refresh.
    /// Call this after external changes to entries (e.g. manual edits, deletions from UI).
    func notifyDataChanged() {
        invalidateCache()
        refreshSnapshot()
    }

    /// Tick-only refresh: recalculates durations without re-fetching entries from DB.
    /// Called by the 1-second heartbeat timer.
    private func tickRefresh() {
        let timestamp = nowProvider()

        // Detect midnight rollover
        let currentDay = aggregationService.calendar.component(.day, from: timestamp)
        if currentDay != lastRefreshDay {
            lastRefreshDay = currentDay
            invalidateCache()
        }

        if entriesDirty {
            // If dirty, do a full refresh instead
            refreshSnapshot()
            return
        }

        // Only recalculate durations from cached entries
        let primaryDuration = primaryRunningEntry.map { max(0, timestamp.timeIntervalSince($0.startAt)) } ?? 0
        metrics.update(
            now: timestamp,
            primarySessionDuration: primaryDuration,
            todayTotalDuration: aggregationService.totalDuration(on: timestamp, entries: cachedTodayEntries, now: timestamp),
            todayWallClockDuration: aggregationService.wallClockDuration(on: timestamp, entries: cachedTodayEntries, now: timestamp)
        )
    }

    func refreshSnapshot() {
        let timestamp = nowProvider()

        let currentDay = aggregationService.calendar.component(.day, from: timestamp)
        lastRefreshDay = currentDay

        // Full re-fetch from DB
        cachedOpenEntries = fetchOpenEntries()
        cachedAllEntries = fetchAllEntries()
        let todayInterval = aggregationService.dayInterval(for: timestamp)
        cachedTodayEntries = cachedAllEntries.filter {
            aggregationService.overlapDuration(of: $0, within: todayInterval, now: timestamp) > 0
        }
        entriesDirty = false

        repairStateIfNeeded(openEntries: cachedOpenEntries)

        publishSnapshot(at: timestamp)
    }

    private func publishSnapshot(at timestamp: Date) {

        let previouslyPausedTasks = Dictionary(uniqueKeysWithValues: pausedTasks.map { ($0.id, $0) })

        // Derive running state from open entries
        runningEntries = cachedOpenEntries
        runningTasks = cachedOpenEntries.compactMap(\.task).uniqued()
        runningCount = runningTasks.count

        // Derive paused tasks
        pausedTasks = timerState.pausedTaskIDs.compactMap { taskID in
            previouslyPausedTasks[taskID] ?? fetchTask(id: taskID)
        }
        pausedCount = pausedTasks.count

        // Resolve primary task
        primaryTask = (runningTasks + pausedTasks).first { $0.id == timerState.primaryTaskID }
            ?? fetchTask(id: timerState.primaryTaskID)
        primaryRunningEntry = cachedOpenEntries.first { $0.task?.id == timerState.primaryTaskID }

        // Duration calculations
        let primaryDuration = primaryRunningEntry.map { max(0, timestamp.timeIntervalSince($0.startAt)) } ?? 0
        metrics.update(
            now: timestamp,
            primarySessionDuration: primaryDuration,
            todayTotalDuration: aggregationService.totalDuration(on: timestamp, entries: cachedTodayEntries, now: timestamp),
            todayWallClockDuration: aggregationService.wallClockDuration(on: timestamp, entries: cachedTodayEntries, now: timestamp)
        )

        // Derive overview status
        if runningCount > 0 {
            timerState.status = .running
        } else if pausedCount > 0 {
            timerState.status = .paused
        } else {
            timerState.status = .idle
        }

        stateStore.save(timerState)
    }

    /// Mark entries cache as stale. Called after any mutation that adds/removes/modifies entries.
    private func invalidateCache() {
        entriesDirty = true
    }

    // MARK: - State repair

    private func repairStateIfNeeded(openEntries: [TimeEntry]) {
        var dirty = false

        // Clean up pausedTaskIDs: remove IDs for tasks that no longer exist
        let invalidPausedIDs = timerState.pausedTaskIDs.filter { fetchTask(id: $0) == nil }
        if !invalidPausedIDs.isEmpty {
            timerState.pausedTaskIDs.subtract(invalidPausedIDs)
            dirty = true
        }

        // A task that is both running (has open entry) and in pausedTaskIDs is contradictory — remove from paused
        let runningTaskIDs = Set(openEntries.compactMap { $0.task?.id })
        let runningAndPaused = timerState.pausedTaskIDs.intersection(runningTaskIDs)
        if !runningAndPaused.isEmpty {
            timerState.pausedTaskIDs.subtract(runningAndPaused)
            dirty = true
        }

        // Validate primaryTaskID: must be running or paused, otherwise rotate
        if let primaryID = timerState.primaryTaskID {
            let isRunning = runningTaskIDs.contains(primaryID)
            let isPaused = timerState.pausedTaskIDs.contains(primaryID)
            let exists = fetchTask(id: primaryID) != nil

            if !exists {
                timerState.primaryTaskID = runningTaskIDs.first
                dirty = true
            } else if !isRunning && !isPaused {
                // Primary points to a stopped task — rotate to a running task if any
                timerState.primaryTaskID = runningTaskIDs.first
                dirty = true
            }
        }

        if dirty {
            stateStore.save(timerState)
        }
    }

    // MARK: - Private helpers

    private func closeEntries(for task: WorkTask, at timestamp: Date) {
        let openEntries = fetchOpenEntries()
        for entry in openEntries where entry.task?.id == task.id {
            if entry.endAt == nil {
                entry.endAt = max(entry.startAt, timestamp)
            }
        }
        task.updatedAt = timestamp
    }

    private func rotatePrimaryAfterPause(task: WorkTask) {
        // After pausing: prefer another running task; if none, keep paused primary
        let openEntries = fetchOpenEntries()
        let otherRunning = openEntries.first { $0.task?.id != task.id }
        if let otherRunning {
            timerState.primaryTaskID = otherRunning.task?.id
        }
        // else: keep the paused task as primary
    }

    private func rotatePrimaryAfterStop() {
        // After stopping: prefer a running task; if none, clear primary
        let openEntries = fetchOpenEntries()
        if let next = openEntries.first {
            timerState.primaryTaskID = next.task?.id
        } else {
            timerState.primaryTaskID = nil
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

    private func fetchAllEntries() -> [TimeEntry] {
        let descriptor = FetchDescriptor<TimeEntry>(
            sortBy: [SortDescriptor(\.startAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func persistAndRefresh() {
        persistenceStore.save(modelContext)
        invalidateCache()
        refreshSnapshot()
    }
}

// MARK: - Array uniquing helper

private extension Array where Element: AnyObject {
    func uniqued() -> [Element] {
        var seen = Set<ObjectIdentifier>()
        return filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
