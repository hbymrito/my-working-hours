import AppKit
import Combine
import SwiftUI

enum MainWindowDestination: Equatable {
    case today
    case overview
    case tasks(UUID?)
    case projects(UUID?)
    case tags(UUID?)
    case records(UUID?)
    case settings
}

@MainActor
final class MainWindowRouter: NSObject, ObservableObject {
    @Published var destination: MainWindowDestination = .today

    private var contentBuilder: (() -> AnyView)?
    private var window: NSWindow?

    func installContentBuilder(_ builder: @escaping () -> AnyView) {
        contentBuilder = builder
    }

    func open(_ destination: MainWindowDestination = .today) {
        self.destination = destination

        let window = ensureWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        guard let contentBuilder else {
            fatalError("Main window content builder must be installed before opening the window.")
        }

        let hostingController = NSHostingController(rootView: contentBuilder())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "My Working Hours"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.setContentSize(NSSize(width: 1320, height: 840))
        window.minSize = NSSize(width: 1080, height: 720)
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        return window
    }
}
