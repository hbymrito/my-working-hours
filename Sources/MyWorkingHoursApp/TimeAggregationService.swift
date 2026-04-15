import Foundation

struct TimeAggregationService {
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func dayInterval(for date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 24 * 60 * 60)
    }

    func overlapDuration(of entry: TimeEntry, within interval: DateInterval, now: Date) -> TimeInterval {
        let entryEnd = entry.endAt ?? now
        let lowerBound = max(entry.startAt, interval.start)
        let upperBound = min(entryEnd, interval.end)

        return max(0, upperBound.timeIntervalSince(lowerBound))
    }

    func totalDuration(on day: Date, entries: [TimeEntry], now: Date) -> TimeInterval {
        let interval = dayInterval(for: day)

        return entries.reduce(into: 0) { total, entry in
            total += overlapDuration(of: entry, within: interval, now: now)
        }
    }

    /// Merge overlapping time segments and return the actual elapsed wall-clock time.
    func wallClockDuration(on day: Date, entries: [TimeEntry], now: Date) -> TimeInterval {
        mergedIntervals(on: day, entries: entries, now: now)
            .reduce(into: 0) { total, interval in
                total += interval.end.timeIntervalSince(interval.start)
            }
    }

    /// Clip entries to the given day, sort by start, then merge overlapping segments.
    func mergedIntervals(on day: Date, entries: [TimeEntry], now: Date) -> [(start: Date, end: Date)] {
        let dayInterval = dayInterval(for: day)

        // Clip each entry to the day boundary
        var segments: [(start: Date, end: Date)] = []
        for entry in entries {
            let effectiveEnd = entry.endAt ?? now
            let clippedStart = max(entry.startAt, dayInterval.start)
            let clippedEnd = min(effectiveEnd, dayInterval.end)
            guard clippedEnd > clippedStart else { continue }
            segments.append((clippedStart, clippedEnd))
        }

        guard !segments.isEmpty else { return [] }

        segments.sort { $0.start < $1.start }

        var merged: [(start: Date, end: Date)] = [segments[0]]
        for segment in segments.dropFirst() {
            if segment.start <= merged[merged.count - 1].end {
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, segment.end)
            } else {
                merged.append(segment)
            }
        }

        return merged
    }

    func totalDuration(for task: WorkTask, entries: [TimeEntry], now: Date) -> TimeInterval {
        entries.reduce(into: 0) { total, entry in
            let endAt = entry.endAt ?? now
            if entry.task?.id == task.id {
                total += max(0, endAt.timeIntervalSince(entry.startAt))
            }
        }
    }

    func groupedDurations(on day: Date, entries: [TimeEntry], now: Date) -> [TaskSummary] {
        let interval = dayInterval(for: day)
        var grouped: [UUID: (task: WorkTask, duration: TimeInterval)] = [:]

        for entry in entries {
            guard let task = entry.task else {
                continue
            }

            let duration = overlapDuration(of: entry, within: interval, now: now)
            guard duration > 0 else {
                continue
            }

            if let existing = grouped[task.id] {
                grouped[task.id] = (existing.task, existing.duration + duration)
            } else {
                grouped[task.id] = (task, duration)
            }
        }

        return grouped.values
            .map { TaskSummary(task: $0.task, duration: $0.duration) }
            .sorted {
                if $0.duration == $1.duration {
                    return $0.task.updatedAt > $1.task.updatedAt
                }

                return $0.duration > $1.duration
            }
    }
}
