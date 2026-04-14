import Foundation
import SwiftData

enum TimeEntrySource: String, Codable, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .automatic: "自动"
        case .manual: "手动"
        }
    }
}

enum TimerStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case running
    case paused

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .idle: "待机"
        case .running: "计时中"
        case .paused: "已暂停"
        }
    }
}

struct TimerState: Codable, Equatable {
    var activeTaskID: UUID?
    var activeEntryStartAt: Date?
    var status: TimerStatus
    var lastInteractionAt: Date

    static func idle(now: Date = .now) -> Self {
        Self(
            activeTaskID: nil,
            activeEntryStartAt: nil,
            status: .idle,
            lastInteractionAt: now
        )
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var isArchived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "新项目",
        colorHex: String = PaletteColor.sky.rawValue,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "新标签",
        colorHex: String = PaletteColor.mint.rawValue,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

@Model
final class WorkTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var project: Project?
    var tags: [Tag]

    init(
        id: UUID = UUID(),
        title: String = "新任务",
        notes: String = "",
        project: Project? = nil,
        tags: [Tag] = [],
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.project = project
        self.tags = tags
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TimeEntry {
    @Attribute(.unique) var id: UUID
    var startAt: Date
    var endAt: Date?
    var source: TimeEntrySource
    var createdAt: Date
    var task: WorkTask?

    init(
        id: UUID = UUID(),
        task: WorkTask? = nil,
        startAt: Date = .now,
        endAt: Date? = nil,
        source: TimeEntrySource = .automatic,
        createdAt: Date = .now
    ) {
        self.id = id
        self.task = task
        self.startAt = startAt
        self.endAt = endAt
        self.source = source
        self.createdAt = createdAt
    }
}
