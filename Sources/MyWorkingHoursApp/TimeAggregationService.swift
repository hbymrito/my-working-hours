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
