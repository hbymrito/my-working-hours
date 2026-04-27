import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let isNotchDisplayEnabled = "MyWorkingHours.Settings.isNotchDisplayEnabled"
        static let isMenuBarTimerDisplayEnabled = "MyWorkingHours.Settings.isMenuBarTimerDisplayEnabled"
    }

    private let defaults: UserDefaults

    @Published var isNotchDisplayEnabled: Bool {
        didSet {
            defaults.set(isNotchDisplayEnabled, forKey: Keys.isNotchDisplayEnabled)
        }
    }

    @Published var isMenuBarTimerDisplayEnabled: Bool {
        didSet {
            defaults.set(isMenuBarTimerDisplayEnabled, forKey: Keys.isMenuBarTimerDisplayEnabled)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isNotchDisplayEnabled = defaults.object(forKey: Keys.isNotchDisplayEnabled) as? Bool ?? true
        isMenuBarTimerDisplayEnabled = defaults.object(forKey: Keys.isMenuBarTimerDisplayEnabled) as? Bool ?? false
    }
}
