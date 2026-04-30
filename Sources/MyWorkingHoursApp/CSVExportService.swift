import Foundation

enum CSVExportService {
    static func makeCSV(from entries: [TimeEntry]) -> String {
        let header = ["开始时间", "结束时间", "时长(分钟)", "任务", "项目", "标签", "备注", "来源"]
        let sorted = entries.sorted { $0.startAt < $1.startAt }

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))

        for entry in sorted {
            let start = dateFormatter.string(from: entry.startAt)
            let end = entry.endAt.map { dateFormatter.string(from: $0) } ?? ""
            let minutes: Int
            if let endAt = entry.endAt {
                minutes = max(0, Int(endAt.timeIntervalSince(entry.startAt) / 60))
            } else {
                minutes = 0
            }
            let task = entry.task?.title ?? ""
            let project = entry.task?.project?.name ?? ""
            let tags = (entry.task?.tags ?? []).map(\.name).joined(separator: ",")
            let notes = entry.task?.notes ?? ""
            let source = entry.source.displayTitle

            let row: [String] = [start, end, String(minutes), task, project, tags, notes, source]
            lines.append(row.map(escape).joined(separator: ","))
        }

        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func suggestedFileName(now: Date = .now) -> String {
        "MyWorkingHours-\(fileNameDateFormatter.string(from: now)).csv"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let fileNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
