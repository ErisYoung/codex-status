import AppKit
import Foundation
import UserNotifications

/// Sends Notification Center alerts for task completion/interruption, with a
/// beep fallback when notifications are unavailable.
///
/// NOTE: intentionally NOT `@MainActor`. Closures formed inside a MainActor
/// method inherit MainActor isolation; `UNUserNotificationCenter` invokes its
/// completion handlers on background queues, which made Swift 6's runtime
/// assert the executor and crash (EXC_BREAKPOINT in
/// `swift_task_isCurrentExecutorImpl`). A nonisolated class keeps the
/// completions nonisolated and safe; we hop to the main actor explicitly.
// All methods are invoked from the main thread (the app is MainActor-driven),
// so sharing the instance across the async authorizationStatus() hop is safe.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private var activated = false

    func activate() {
        guard !activated else { return }
        activated = true
        StatusLog.write("activate: canUseNotifications=\(canUseNotifications) bundleId=\(Bundle.main.bundleIdentifier ?? "nil")")
        guard canUseNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            StatusLog.write("activate requestAuthorization result: granted=\(granted) error=\(error?.localizedDescription ?? "nil")")
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard canUseNotifications else { return .denied }
        return await withCheckedContinuation { continuation in
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                let status = settings.authorizationStatus
                StatusLog.write("authorizationStatus=\(status.rawValue) (\(status))")
                continuation.resume(returning: status)
            }
        }
    }

    func send(title: String, body: String) {
        guard canUseNotifications else {
            DispatchQueue.main.async { NSSound.beep() }
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            StatusLog.write("send: settings status=\(settings.authorizationStatus.rawValue) (\(settings.authorizationStatus))")
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliver(title: title, body: body, center: center)
            case .notDetermined:
                // First send doubles as the permission request.
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    StatusLog.write("send requestAuthorization: granted=\(granted)")
                    if granted {
                        self.deliver(title: title, body: body, center: center)
                    } else {
                        self.deliverLegacy(title: title, body: body)
                    }
                }
            default:
                // macOS 15 denies ad-hoc signed apps notification permission
                // outright; the legacy API still delivers without permission.
                self.deliverLegacy(title: title, body: body)
            }
        }
    }

    private func deliverLegacy(title: String, body: String) {
        StatusLog.write("deliverLegacy: NSUserNotification '\(title)'")
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func deliver(title: String, body: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
        StatusLog.write("deliver: added notification '\(title)'")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// `UNUserNotificationCenter.current()` raises an NSInternalInconsistency-
    /// Exception when the process has no app bundle (e.g. a bare binary run
    /// from the terminal). Skip notifications and fall back to beeping.
    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }
}
