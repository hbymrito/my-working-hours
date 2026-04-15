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

/// Per-task display state, derived by the View layer from Engine's `isTaskRunning` / `isTaskPaused`.
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
    var primaryTaskID: UUID?
    var pausedTaskIDs: Set<UUID>
    var lastInteractionAt: Date

    /// Derived overview status, updated by TimerEngine before each save.
    /// Used by UI compat shims — not the source of truth for parallel state.
    var status: TimerStatus = .idle

    private enum CodingKeys: String, CodingKey {
        case primaryTaskID, pausedTaskIDs, lastInteractionAt
    }

    static func idle(now: Date = .now) -> Self {
        Self(primaryTaskID: nil, pausedTaskIDs: [], lastInteractionAt: now)
    }

    // MARK: - Migration from v1 format

    private struct V1: Decodable {
        var activeTaskID: UUID?
        var activeEntryStartAt: Date?
        var status: TimerStatus
        var lastInteractionAt: Date
    }

    init(primaryTaskID: UUID? = nil, pausedTaskIDs: Set<UUID> = [], lastInteractionAt: Date = .now) {
        self.primaryTaskID = primaryTaskID
        self.pausedTaskIDs = pausedTaskIDs
        self.lastInteractionAt = lastInteractionAt
    }

    init(from decoder: Decoder) throws {
        // Try new format first
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let primaryTaskID = try? container.decodeIfPresent(UUID.self, forKey: .primaryTaskID),
           let pausedTaskIDs = try? container.decode(Set<UUID>.self, forKey: .pausedTaskIDs),
           let lastInteractionAt = try? container.decode(Date.self, forKey: .lastInteractionAt)
        {
            self.primaryTaskID = primaryTaskID
            self.pausedTaskIDs = pausedTaskIDs
            self.lastInteractionAt = lastInteractionAt
            return
        }

        // Fall back to v1 format
        let v1 = try V1(from: decoder)
        self.primaryTaskID = v1.activeTaskID
        self.lastInteractionAt = v1.lastInteractionAt

        if v1.status == .paused, let taskID = v1.activeTaskID {
            self.pausedTaskIDs = [taskID]
        } else {
            self.pausedTaskIDs = []
        }
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
