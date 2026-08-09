import Foundation

enum Settings {
    static let notificationsEnabledKey = "notificationsEnabled"
    static let launchAtLoginKey = "launchAtLogin"

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notificationsEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }

    static let pollInterval: TimeInterval = 2
    static let staleAfter: TimeInterval = 600
    static let idleWindow: TimeInterval = 1800
}
