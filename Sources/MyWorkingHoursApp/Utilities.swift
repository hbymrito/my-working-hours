import AppKit
import Foundation
import SwiftUI

enum PaletteColor: String, CaseIterable, Identifiable {
    case sky = "#8EB7FF"
    case mint = "#73D7C6"
    case lemon = "#F5C75B"
    case coral = "#F28E7C"
    case lilac = "#C6B3FF"
    case slate = "#8F99B2"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sky: "天青"
        case .mint: "薄荷"
        case .lemon: "琥珀"
        case .coral: "珊瑚"
        case .lilac: "丁香"
        case .slate: "石板"
        }
    }

    var color: Color {
        Color(hexString: rawValue)
    }
}

struct TaskSummary: Identifiable {
    let task: WorkTask
    let duration: TimeInterval

    var id: UUID { task.id }
}

struct ProjectSummary: Identifiable {
    let project: Project?
    let duration: TimeInterval

    var id: String { project?.id.uuidString ?? "unassigned" }
    var displayName: String { project?.name ?? "无项目" }
    var colorHex: String { project?.colorHex ?? PaletteColor.slate.rawValue }
}

struct TagSummary: Identifiable {
    let tag: Tag
    let duration: TimeInterval

    var id: UUID { tag.id }
}

enum OverviewPeriod: String, CaseIterable, Identifiable, Hashable {
    case today
    case week
    case month
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .week: "本周"
        case .month: "本月"
        case .custom: "自定义"
        }
    }
}

enum DurationTextFormatter {
    private static let clockFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    private static let compactFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static func clock(_ duration: TimeInterval) -> String {
        clockFormatter.string(from: max(0, duration)) ?? "00:00:00"
    }

    static func compact(_ duration: TimeInterval) -> String {
        compactFormatter.string(from: max(0, duration)) ?? "0m"
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    init(hexString: String) {
        self = Color(nsColor: NSColor(hexString: hexString) ?? .systemBlue)
    }
}

extension TimerStatus {
    var symbolName: String {
        switch self {
        case .idle: "circle.dotted"
        case .running: "record.circle.fill"
        case .paused: "pause.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .secondary
        case .running: Color(hexString: PaletteColor.mint.rawValue)
        case .paused: Color(hexString: PaletteColor.lemon.rawValue)
        }
    }
}

extension Date {
    func shortTimeText() -> String {
        formatted(date: .omitted, time: .shortened)
    }

    func shortDateText() -> String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

func formattedTimeRange(start: Date, end: Date?) -> String {
    if let end {
        if Calendar.autoupdatingCurrent.isDate(start, inSameDayAs: end) {
            return "\(start.shortTimeText()) - \(end.shortTimeText())"
        }

        return "\(start.shortDateText()) \(start.shortTimeText()) - \(end.shortDateText()) \(end.shortTimeText())"
    }

    return "\(start.shortTimeText()) - 进行中"
}

extension NSScreen {
    var notchRect: NSRect? {
        let metrics = notchMetrics
        guard metrics.hasPhysicalNotch else {
            return nil
        }

        return notchOverlayGeometry.anchorRect
    }

    var topCenterAnchorRect: NSRect {
        notchOverlayGeometry.anchorRect
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        screens.first(where: { $0.frame.contains(point) })
    }
}

struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 16)
    }
}

struct StatusPill: View {
    let status: TimerStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .font(.system(size: 11, weight: .bold))
            Text(status.displayTitle)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct TagPill: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hexString: tag.colorHex))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hexString: tag.colorHex).opacity(0.14), in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.12), lineWidth: 1)
        }
    }
}

struct SoftCapsuleButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(configuration.isPressed ? 0.95 : 1), tint.opacity(configuration.isPressed ? 0.82 : 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.06 : 0.24), lineWidth: 1)
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.24), radius: configuration.isPressed ? 10 : 18, y: configuration.isPressed ? 5 : 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct ActionCapsuleButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var foreground: Color = .white
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftCapsuleButtonStyle(tint: isEnabled ? tint : .gray.opacity(0.35), foreground: isEnabled ? foreground : .white.opacity(0.6)))
        .disabled(!isEnabled)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
