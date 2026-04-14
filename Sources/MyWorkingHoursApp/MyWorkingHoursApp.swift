import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class AppServices: ObservableObject {
    let persistenceStore: PersistenceStore
    let aggregationService: TimeAggregationService
    let mainWindowRouter: MainWindowRouter
    let timerEngine: TimerEngine
    let notchOverlayController: NotchOverlayController

    init() {
        persistenceStore = PersistenceStore()
        aggregationService = TimeAggregationService()
        mainWindowRouter = MainWindowRouter()
        timerEngine = TimerEngine(
            context: persistenceStore.modelContainer.mainContext,
            persistenceStore: persistenceStore,
            aggregationService: aggregationService
        )
        notchOverlayController = NotchOverlayController(
            timerEngine: timerEngine,
            mainWindowRouter: mainWindowRouter
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

        services.mainWindowRouter.installContentBuilder { [unowned router] in
            AnyView(
                MainWindowView()
                    .environmentObject(engine)
                    .environmentObject(router)
                    .modelContainer(container)
            )
        }

        _services = StateObject(wrappedValue: services)

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
                .modelContainer(services.persistenceStore.modelContainer)
        } label: {
            MenuBarLabelView()
                .environmentObject(services.timerEngine)
        }
        .menuBarExtraStyle(.window)
    }
}
