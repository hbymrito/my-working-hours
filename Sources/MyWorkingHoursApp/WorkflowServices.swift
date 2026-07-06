import Foundation
import SwiftData

enum TimelineAnomaly: String, CaseIterable, Hashable {
    case short
    case long
    case overlapping
    case crossesMidnight
}

struct TimelineItem: Identifiable, Equatable {
    let entryID: UUID
    let start: Date
    let end: Date
    let laneIndex: Int
    let laneCount: Int
    let anomalies: Set<TimelineAnomaly>

    var id: UUID { entryID }
}

struct TimeEntryMergeSuggestion: Identifiable, Equatable {
    let entryIDs: [UUID]
    let taskID: UUID
    let taskTitle: String
    let start: Date
    let end: Date
    let includedGapDuration: TimeInterval

    var id: UUID { entryIDs[0] }
}

struct TimelineDayAnalysis {
    let items: [TimelineItem]
    let mergeSuggestions: [TimeEntryMergeSuggestion]
}

struct TimelineWorkflowService {
    let calendar: Calendar
    let shortDuration: TimeInterval
    let longDuration: TimeInterval
    let mergeGap: TimeInterval

    init(
        calendar: Calendar = .autoupdatingCurrent,
        shortDuration: TimeInterval = 60,
        longDuration: TimeInterval = 4 * 60 * 60,
        mergeGap: TimeInterval = 5 * 60
    ) {
        self.calendar = calendar
        self.shortDuration = shortDuration
        self.longDuration = longDuration
        self.mergeGap = mergeGap
    }

    func analyze(day: Date, entries: [TimeEntry], now: Date) -> TimelineDayAnalysis {
        let dayInterval = calendar.dateInterval(of: .day, for: day)
            ?? DateInterval(start: day, duration: 24 * 60 * 60)

        var candidates = entries.compactMap { entry -> Candidate? in
            let effectiveEnd = entry.endAt ?? now
            let start = max(entry.startAt, dayInterval.start)
            let end = min(effectiveEnd, dayInterval.end)
            guard end > start else { return nil }

            let duration = max(0, effectiveEnd.timeIntervalSince(entry.startAt))
            var anomalies: Set<TimelineAnomaly> = []
            if duration < shortDuration {
                anomalies.insert(.short)
            }
            if duration > longDuration {
                anomalies.insert(.long)
            }
            if entry.startAt < dayInterval.start || effectiveEnd > dayInterval.end {
                anomalies.insert(.crossesMidnight)
            }

            return Candidate(entry: entry, start: start, end: end, anomalies: anomalies)
        }
        .sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }

        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                if candidates[secondIndex].start >= candidates[firstIndex].end {
                    break
                }
                if candidates[firstIndex].start < candidates[secondIndex].end {
                    candidates[firstIndex].anomalies.insert(.overlapping)
                    candidates[secondIndex].anomalies.insert(.overlapping)
                }
            }
        }

        return TimelineDayAnalysis(
            items: layout(candidates),
            mergeSuggestions: mergeSuggestions(in: entries, dayInterval: dayInterval)
        )
    }

    private func layout(_ candidates: [Candidate]) -> [TimelineItem] {
        guard !candidates.isEmpty else { return [] }

        var result: [TimelineItem] = []
        var clusterStart = 0

        while clusterStart < candidates.count {
            var clusterEnd = clusterStart + 1
            var latestEnd = candidates[clusterStart].end

            while clusterEnd < candidates.count, candidates[clusterEnd].start < latestEnd {
                latestEnd = max(latestEnd, candidates[clusterEnd].end)
                clusterEnd += 1
            }

            let cluster = candidates[clusterStart..<clusterEnd]
            var laneEnds: [Date] = []
            var assignments: [(candidate: Candidate, laneIndex: Int)] = []

            for candidate in cluster {
                if let availableLane = laneEnds.firstIndex(where: { $0 <= candidate.start }) {
                    laneEnds[availableLane] = candidate.end
                    assignments.append((candidate, availableLane))
                } else {
                    laneEnds.append(candidate.end)
                    assignments.append((candidate, laneEnds.count - 1))
                }
            }

            let laneCount = laneEnds.count
            result.append(contentsOf: assignments.map {
                TimelineItem(
                    entryID: $0.candidate.entry.id,
                    start: $0.candidate.start,
                    end: $0.candidate.end,
                    laneIndex: $0.laneIndex,
                    laneCount: laneCount,
                    anomalies: $0.candidate.anomalies
                )
            })
            clusterStart = clusterEnd
        }

        return result
    }

    private func mergeSuggestions(in entries: [TimeEntry], dayInterval: DateInterval) -> [TimeEntryMergeSuggestion] {
        let eligible = entries.filter { entry in
            guard let endAt = entry.endAt else { return false }
            return entry.startAt >= dayInterval.start && endAt <= dayInterval.end && endAt > entry.startAt
        }

        let byTask = Dictionary(grouping: eligible) { $0.task?.id }
        var suggestions: [TimeEntryMergeSuggestion] = []

        for (taskID, taskEntries) in byTask {
            guard let taskID, let taskTitle = taskEntries.first?.task?.title else { continue }
            let sorted = taskEntries.sorted { $0.startAt < $1.startAt }
            var chain: [TimeEntry] = []

            func appendChainIfNeeded() {
                guard chain.count >= 2, let first = chain.first, let last = chain.last, let lastEnd = last.endAt else {
                    return
                }

                let coveredDuration = chain.reduce(into: 0.0) { total, entry in
                    total += max(0, (entry.endAt ?? entry.startAt).timeIntervalSince(entry.startAt))
                }
                suggestions.append(
                    TimeEntryMergeSuggestion(
                        entryIDs: chain.map(\.id),
                        taskID: taskID,
                        taskTitle: taskTitle,
                        start: first.startAt,
                        end: lastEnd,
                        includedGapDuration: max(0, lastEnd.timeIntervalSince(first.startAt) - coveredDuration)
                    )
                )
            }

            for entry in sorted {
                guard let previous = chain.last, let previousEnd = previous.endAt else {
                    chain = [entry]
                    continue
                }

                let gap = entry.startAt.timeIntervalSince(previousEnd)
                if gap >= 0, gap <= mergeGap {
                    chain.append(entry)
                } else {
                    appendChainIfNeeded()
                    chain = [entry]
                }
            }
            appendChainIfNeeded()
        }

        return suggestions.sorted { $0.start < $1.start }
    }

    private struct Candidate {
        let entry: TimeEntry
        let start: Date
        let end: Date
        var anomalies: Set<TimelineAnomaly>
    }
}

enum WorkflowMutationError: Error {
    case staleMergeSuggestion
}

@MainActor
struct TimeEntryMaintenanceService {
    let modelContext: ModelContext

    @discardableResult
    func merge(_ suggestion: TimeEntryMergeSuggestion, entries: [TimeEntry]) throws -> TimeEntry {
        let selected = entries
            .filter { suggestion.entryIDs.contains($0.id) }
            .sorted { $0.startAt < $1.startAt }

        guard selected.count == suggestion.entryIDs.count,
              selected.count >= 2,
              selected.allSatisfy({ $0.task?.id == suggestion.taskID && $0.endAt != nil }) else {
            throw WorkflowMutationError.staleMergeSuggestion
        }

        for pair in zip(selected, selected.dropFirst()) {
            guard let firstEnd = pair.0.endAt else {
                throw WorkflowMutationError.staleMergeSuggestion
            }
            let gap = pair.1.startAt.timeIntervalSince(firstEnd)
            guard gap >= 0, gap <= 5 * 60 else {
                throw WorkflowMutationError.staleMergeSuggestion
            }
        }

        guard let survivor = selected.first, let finalEnd = selected.last?.endAt else {
            throw WorkflowMutationError.staleMergeSuggestion
        }

        survivor.endAt = finalEnd
        survivor.source = .manual
        selected.dropFirst().forEach(modelContext.delete)

        do {
            try modelContext.save()
            return survivor
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

struct TaskArchiveBuckets {
    let active: [WorkTask]
    let suggested: [WorkTask]
    let archived: [WorkTask]
}

struct TaskWorkflowService {
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func archiveBuckets(
        tasks: [WorkTask],
        entries: [TimeEntry],
        activeTaskIDs: Set<UUID>,
        now: Date,
        inactiveDays: Int = 30
    ) -> TaskArchiveBuckets {
        let cutoff = calendar.date(byAdding: .day, value: -inactiveDays, to: now)
            ?? now.addingTimeInterval(-TimeInterval(inactiveDays * 24 * 60 * 60))
        var lastEntryByTask: [UUID: Date] = [:]
        for entry in entries {
            guard let taskID = entry.task?.id else { continue }
            let usedAt = entry.endAt ?? entry.startAt
            if usedAt > (lastEntryByTask[taskID] ?? .distantPast) {
                lastEntryByTask[taskID] = usedAt
            }
        }

        var active: [WorkTask] = []
        var suggested: [WorkTask] = []
        var archived: [WorkTask] = []

        for task in tasks {
            if task.isArchived {
                archived.append(task)
                continue
            }

            let lastUsedAt = lastEntryByTask[task.id] ?? task.createdAt
            if !activeTaskIDs.contains(task.id), lastUsedAt <= cutoff {
                suggested.append(task)
            } else {
                active.append(task)
            }
        }

        active.sort { $0.updatedAt > $1.updatedAt }
        suggested.sort {
            (lastEntryByTask[$0.id] ?? $0.createdAt) < (lastEntryByTask[$1.id] ?? $1.createdAt)
        }
        archived.sort { $0.updatedAt > $1.updatedAt }

        return TaskArchiveBuckets(active: active, suggested: suggested, archived: archived)
    }

    func filterQuickTasks(_ tasks: [WorkTask], query: String) -> [WorkTask] {
        let available = tasks.filter { !$0.isArchived }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return available }

        let queryTicket = ticketIdentifier(in: trimmed)
        return available.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed)
                || (task.project?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (queryTicket != nil && ticketIdentifier(in: task.title) == queryTicket)
        }
    }

    func duplicateCandidates(for title: String, tasks: [WorkTask], selectedProjectID: UUID?) -> [WorkTask] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty else { return [] }
        let ticket = ticketIdentifier(in: title)

        return tasks
            .filter { task in
                guard !task.isArchived else { return false }
                let exactTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
                let sameTicket = ticket != nil && ticketIdentifier(in: task.title) == ticket
                return exactTitle || sameTicket
            }
            .sorted {
                let leftPreferred = $0.project?.id == selectedProjectID
                let rightPreferred = $1.project?.id == selectedProjectID
                if leftPreferred != rightPreferred { return leftPreferred }
                return $0.updatedAt > $1.updatedAt
            }
    }

    func ticketIdentifier(in text: String) -> String? {
        let uppercased = text.uppercased()
        guard let marker = uppercased.range(of: "YT") else { return nil }

        var digits = ""
        for character in uppercased[marker.upperBound...] {
            if character.isNumber {
                digits.append(character)
                if digits.count == 5 { return "YT" + digits }
            } else if !digits.isEmpty {
                break
            }
        }
        return nil
    }
}
