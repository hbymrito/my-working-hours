import AppKit
import CoreGraphics

enum NotchOverlayPresentationMode {
    case hidden
    case peek
    case pinned
}

enum NotchOverlayChromeStyle {
    case physicalNotch
    case simulatedNotch
}

struct ScreenNotchMetrics: Equatable, Sendable {
    static let fallbackClosedHeight: CGFloat = 32
    static let fallbackNotchWidth: CGFloat = 180
    static let fallbackSize = CGSize(width: 224, height: 38)

    let size: CGSize
    let hasPhysicalNotch: Bool

    var closedHeight: CGFloat {
        hasPhysicalNotch ? size.height : Self.fallbackClosedHeight
    }

    static func detect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) -> ScreenNotchMetrics {
        let detectedHeight = ceil(safeAreaTop)
        guard detectedHeight > 0 else {
            return ScreenNotchMetrics(size: Self.fallbackSize, hasPhysicalNotch: false)
        }

        let leftPadding = max(0, auxiliaryTopLeftWidth ?? 0)
        let rightPadding = max(0, auxiliaryTopRightWidth ?? 0)
        let detectedWidth: CGFloat

        if leftPadding > 0, rightPadding > 0 {
            detectedWidth = max(
                Self.fallbackNotchWidth,
                ceil(screenFrame.width - leftPadding - rightPadding + 4)
            )
        } else {
            detectedWidth = Self.fallbackNotchWidth
        }

        return ScreenNotchMetrics(
            size: CGSize(width: detectedWidth, height: detectedHeight),
            hasPhysicalNotch: true
        )
    }
}

struct NotchOverlayGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let metrics: ScreenNotchMetrics

    var chromeStyle: NotchOverlayChromeStyle {
        metrics.hasPhysicalNotch ? .physicalNotch : .simulatedNotch
    }

    var anchorRect: CGRect {
        if metrics.hasPhysicalNotch {
            return CGRect(
                x: screenFrame.midX - metrics.size.width / 2,
                y: screenFrame.maxY - metrics.size.height,
                width: metrics.size.width,
                height: metrics.size.height
            )
        }

        return CGRect(
            x: screenFrame.midX - metrics.size.width / 2,
            y: screenFrame.maxY - metrics.closedHeight,
            width: metrics.size.width,
            height: metrics.closedHeight
        )
    }

    var hitTargetFrame: CGRect {
        let anchor = anchorRect
        let width = max(anchor.width + 140, 280)
        let height = max(anchor.height + 10, 34)

        return CGRect(
            x: anchor.midX - width / 2,
            y: anchor.maxY - height,
            width: width,
            height: height
        )
    }

    func hiddenOverlayFrame() -> CGRect {
        positionedOverlayFrame(size: hiddenOverlaySize, mode: .hidden)
    }

    func overlayFrame(for mode: NotchOverlayPresentationMode) -> CGRect {
        switch mode {
        case .hidden:
            return positionedOverlayFrame(size: hiddenOverlaySize, mode: mode)
        case .peek, .pinned:
            return positionedOverlayFrame(size: expandedOverlaySize, mode: mode)
        }
    }

    private var hiddenOverlaySize: CGSize {
        CGSize(width: 260, height: 44)
    }

    private var expandedOverlaySize: CGSize {
        CGSize(width: 520, height: metrics.hasPhysicalNotch ? 68 : 32)
    }

    private func positionedOverlayFrame(size: CGSize, mode: NotchOverlayPresentationMode) -> CGRect {
        let anchor = anchorRect

        return CGRect(
            x: anchor.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension NSScreen {
    var notchMetrics: ScreenNotchMetrics {
        ScreenNotchMetrics.detect(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width
        )
    }

    var notchOverlayGeometry: NotchOverlayGeometry {
        NotchOverlayGeometry(
            screenFrame: frame,
            visibleFrame: visibleFrame,
            metrics: notchMetrics
        )
    }
}
