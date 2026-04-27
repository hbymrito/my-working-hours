import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            onReopen?()
        }
        return true
    }
}

@MainActor
final class AppServices: ObservableObject {
    let persistenceStore: PersistenceStore
    let aggregationService: TimeAggregationService
    let mainWindowRouter: MainWindowRouter
    let timerEngine: TimerEngine
    let notchOverlayController: NotchOverlayController
    let appSettings: AppSettings

    init() {
        persistenceStore = PersistenceStore()
        aggregationService = TimeAggregationService()
        mainWindowRouter = MainWindowRouter()
        appSettings = AppSettings()
        timerEngine = TimerEngine(
            context: persistenceStore.modelContainer.mainContext,
            persistenceStore: persistenceStore,
            aggregationService: aggregationService
        )
        notchOverlayController = NotchOverlayController(
            timerEngine: timerEngine,
            mainWindowRouter: mainWindowRouter,
            settings: appSettings
        )
    }

    func start() {
        timerEngine.activate()
        notchOverlayController.activate()
    }
}

@main
struct MyWorkingHoursApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services: AppServices

    init() {
        let services = AppServices()
        let container = services.persistenceStore.modelContainer
        let engine = services.timerEngine
        let router = services.mainWindowRouter
        let settings = services.appSettings

        services.mainWindowRouter.installContentBuilder { [unowned router] in
            AnyView(
                MainWindowView()
                    .environmentObject(engine)
                    .environmentObject(router)
                    .environmentObject(settings)
                    .modelContainer(container)
            )
        }

        _services = StateObject(wrappedValue: services)

        appDelegate.onReopen = { [weak router] in
            router?.open()
        }

        DispatchQueue.main.async {
            services.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(services.timerEngine)
                .environmentObject(services.notchOverlayController)
                .environmentObject(services.mainWindowRouter)
                .environmentObject(services.appSettings)
                .modelContainer(services.persistenceStore.modelContainer)
        } label: {
            MenuBarLabelView()
                .environmentObject(services.timerEngine)
                .environmentObject(services.appSettings)
        }
        .menuBarExtraStyle(.window)
    }
}
