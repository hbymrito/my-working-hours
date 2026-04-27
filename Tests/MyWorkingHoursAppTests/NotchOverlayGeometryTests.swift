import CoreGraphics
import XCTest
@testable import MyWorkingHoursApp

final class NotchOverlayGeometryTests: XCTestCase {
    func testScreenNotchMetricsDetectsPhysicalNotchFromSafeAreaAndAuxiliaryWidths() {
        let metrics = ScreenNotchMetrics.detect(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeftWidth: 620,
            auxiliaryTopRightWidth: 620
        )

        XCTAssertTrue(metrics.hasPhysicalNotch)
        XCTAssertEqual(metrics.size, CGSize(width: 276, height: 38))
        XCTAssertEqual(metrics.closedHeight, 38)
    }

    func testScreenNotchMetricsFallsBackForNonNotchDisplay() {
        let metrics = ScreenNotchMetrics.detect(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )

        XCTAssertFalse(metrics.hasPhysicalNotch)
        XCTAssertEqual(metrics.size, ScreenNotchMetrics.fallbackSize)
        XCTAssertEqual(metrics.closedHeight, ScreenNotchMetrics.fallbackClosedHeight)
    }

    func testNotchGeometryCentersPhysicalNotchFramesAtTopEdge() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let metrics = ScreenNotchMetrics.detect(
            screenFrame: screenFrame,
            safeAreaTop: 38,
            auxiliaryTopLeftWidth: 620,
            auxiliaryTopRightWidth: 620
        )
        let geometry = NotchOverlayGeometry(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            metrics: metrics
        )

        XCTAssertEqual(geometry.chromeStyle, .physicalNotch)
        XCTAssertEqual(geometry.anchorRect, CGRect(x: 618, y: 944, width: 276, height: 38))

        let hitFrame = geometry.hitTargetFrame
        XCTAssertEqual(hitFrame.maxY, screenFrame.maxY)
        XCTAssertGreaterThanOrEqual(hitFrame.width, metrics.size.width + 140)
        XCTAssertTrue(hitFrame.contains(CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 1)))
        XCTAssertTrue(hitFrame.contains(CGPoint(x: screenFrame.midX, y: screenFrame.maxY - metrics.size.height)))

        let openedFrame = geometry.overlayFrame(for: .peek)
        XCTAssertEqual(openedFrame, CGRect(x: 496, y: 914, width: 520, height: 68))
        XCTAssertEqual(openedFrame.maxY, screenFrame.maxY)
    }

    func testNotchGeometryUsesSimulatedNotchForNonNotchDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 872)
        let metrics = ScreenNotchMetrics.detect(
            screenFrame: screenFrame,
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )
        let geometry = NotchOverlayGeometry(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            metrics: metrics
        )

        XCTAssertEqual(geometry.chromeStyle, .simulatedNotch)
        XCTAssertEqual(geometry.anchorRect, CGRect(x: 608, y: 868, width: 224, height: 32))

        let hitFrame = geometry.hitTargetFrame
        XCTAssertEqual(hitFrame, CGRect(x: 538, y: 858, width: 364, height: 42))

        let openedFrame = geometry.overlayFrame(for: .pinned)
        XCTAssertEqual(openedFrame, CGRect(x: 460, y: 868, width: 520, height: 32))
        XCTAssertEqual(openedFrame.maxY, screenFrame.maxY)
    }
}
