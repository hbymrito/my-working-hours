import AppKit
import SwiftUI

@MainActor
final class NotchOverlayController: NSObject, ObservableObject {
    enum PresentationMode {
        case hidden
        case peek
        case pinned
    }

    @Published private(set) var mode: PresentationMode = .hidden
    @Published var isTaskSwitcherPresented = false

    private let timerEngine: TimerEngine
    private let mainWindowRouter: MainWindowRouter

    private weak var hitPanel: HitTargetPanel?
    private weak var overlayPanel: OverlayFloatingPanel?
    private var panelObservers: [NSObjectProtocol] = []
    private var escapeKeyMonitor: Any?
    private var hoverOnHitTarget = false
    private var hoverOnOverlay = false
    private var hideWorkItem: DispatchWorkItem?

    init(timerEngine: TimerEngine, mainWindowRouter: MainWindowRouter) {
        self.timerEngine = timerEngine
        self.mainWindowRouter = mainWindowRouter
        super.init()
    }

    func activate() {
        rebuildPanels()

        panelObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.rebuildPanels()
                }
            }
        )

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }

            DispatchQueue.main.async { [weak self] in
                if self?.mode == .pinned {
                    self?.hide()
                }
            }

            return event
        }
    }

    func togglePinned() {
        switch mode {
        case .hidden, .peek:
            showPinned()
        case .pinned:
            hide()
        }
    }

    func showPinned() {
        guard targetScreen()?.notchRect != nil else {
            return
        }

        hideWorkItem?.cancel()
        mode = .pinned
        updatePanels(animated: true)
        overlayPanel?.makeKeyAndOrderFront(nil)
    }

    func showPeek() {
        guard mode != .pinned, targetScreen()?.notchRect != nil else {
            return
        }

        hideWorkItem?.cancel()
        mode = .peek
        updatePanels(animated: true)
    }

    func hide() {
        hideWorkItem?.cancel()
        isTaskSwitcherPresented = false
        mode = .hidden
        updatePanels(animated: true)
    }

    func overlayHoverChanged(_ isHovering: Bool) {
        hoverOnOverlay = isHovering

        if isHovering {
            hideWorkItem?.cancel()
        } else {
            scheduleHideIfNeeded()
        }
    }

    func openMainWindow() {
        if let activeTask = timerEngine.activeTask {
            mainWindowRouter.open(.tasks(activeTask.id))
        } else {
            mainWindowRouter.open(.today)
        }
    }

    private func rebuildPanels() {
        hitPanel?.close()
        overlayPanel?.close()

        guard let screen = targetScreen(), let notchRect = screen.notchRect else {
            return
        }

        let hitPanel = HitTargetPanel(contentRect: hitTargetFrame(for: notchRect), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hitPanel.backgroundColor = .clear
        hitPanel.isOpaque = false
        hitPanel.level = .statusBar
        hitPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let tracker = InteractionTrackingView(frame: NSRect(origin: .zero, size: hitPanel.frame.size))
        tracker.autoresizingMask = [.width, .height]
        tracker.onHoverChanged = { [weak self] hovering in
            DispatchQueue.main.async { [weak self] in
                self?.hoverOnHitTarget = hovering

                if hovering {
                    self?.showPeek()
                } else {
                    self?.scheduleHideIfNeeded()
                }
            }
        }
        tracker.onClick = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.togglePinned()
            }
        }
        hitPanel.contentView = tracker
        hitPanel.orderFrontRegardless()
        self.hitPanel = hitPanel

        let overlayPanel = OverlayFloatingPanel(contentRect: hiddenOverlayFrame(for: notchRect), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        overlayPanel.backgroundColor = .clear
        overlayPanel.isOpaque = false
        overlayPanel.hasShadow = false
        overlayPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.isMovableByWindowBackground = false
        overlayPanel.contentView = NSHostingView(
            rootView: NotchOverlayView()
                .environmentObject(timerEngine)
                .environmentObject(self)
                .environmentObject(mainWindowRouter)
        )
        overlayPanel.orderOut(nil)
        self.overlayPanel = overlayPanel

        updatePanels(animated: false)
    }

    private func updatePanels(animated: Bool) {
        guard let hitPanel,
              let overlayPanel,
              let screen = targetScreen(),
              let notchRect = screen.notchRect
        else {
            return
        }

        hitPanel.setFrame(hitTargetFrame(for: notchRect), display: true)

        let visibleFrame = overlayFrame(for: notchRect, mode: mode == .hidden ? .peek : mode)
        let collapsedFrame = hiddenOverlayFrame(for: notchRect)

        switch mode {
        case .hidden:
            guard overlayPanel.isVisible else {
                return
            }

            let animations = {
                overlayPanel.animator().alphaValue = 0
                overlayPanel.animator().setFrame(collapsedFrame, display: true)
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    animations()
                } completionHandler: {
                    DispatchQueue.main.async {
                        overlayPanel.orderOut(nil)
                    }
                }
            } else {
                overlayPanel.alphaValue = 0
                overlayPanel.setFrame(collapsedFrame, display: true)
                overlayPanel.orderOut(nil)
            }

        case .peek, .pinned:
            if !overlayPanel.isVisible {
                overlayPanel.alphaValue = 0
                overlayPanel.setFrame(collapsedFrame, display: false)
                overlayPanel.orderFrontRegardless()
            }

            let animations = {
                overlayPanel.animator().alphaValue = 1
                overlayPanel.animator().setFrame(visibleFrame, display: true)
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.26
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    animations()
                }
            } else {
                overlayPanel.alphaValue = 1
                overlayPanel.setFrame(visibleFrame, display: true)
            }
        }
    }

    private func scheduleHideIfNeeded() {
        guard mode != .pinned else {
            return
        }

        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            if !hoverOnHitTarget, !hoverOnOverlay, mode != .pinned {
                hide()
            }
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func targetScreen() -> NSScreen? {
        if let hoveredScreen = NSScreen.screen(containing: NSEvent.mouseLocation), hoveredScreen.notchRect != nil {
            return hoveredScreen
        }

        if let mainScreen = NSScreen.main, mainScreen.notchRect != nil {
            return mainScreen
        }

        return NSScreen.screens.first(where: { $0.notchRect != nil })
    }

    private func hitTargetFrame(for notchRect: NSRect) -> NSRect {
        let width = max(notchRect.width + 92, 210)
        let height = max(notchRect.height + 10, 34)

        return NSRect(
            x: notchRect.midX - (width / 2),
            y: notchRect.minY - 4,
            width: width,
            height: height
        )
    }

    private func hiddenOverlayFrame(for notchRect: NSRect) -> NSRect {
        let width: CGFloat = 220
        let height: CGFloat = 48

        return NSRect(
            x: notchRect.midX - (width / 2),
            y: notchRect.minY - height + 22,
            width: width,
            height: height
        )
    }

    private func overlayFrame(for notchRect: NSRect, mode: PresentationMode) -> NSRect {
        let width: CGFloat
        let height: CGFloat

        switch mode {
        case .hidden:
            width = 220
            height = 48
        case .peek:
            width = 390
            height = 280
        case .pinned:
            width = 470
            height = 390
        }

        return NSRect(
            x: notchRect.midX - (width / 2),
            y: notchRect.minY - height + 24,
            width: width,
            height: height
        )
    }
}

private final class HitTargetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class InteractionTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseEnteredAndExited]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }
}
