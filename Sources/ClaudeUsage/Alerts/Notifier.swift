import Foundation
import UserNotifications

protocol Notifier: Sendable {
    func send(title: String, body: String, playSound: Bool) async
}

struct NoopNotifier: Notifier {
    func send(title: String, body: String, playSound: Bool) async {}
}

enum NotificationPermission: Sendable, Equatable {
    case unavailable      // not running as a packaged app, so macOS has no bundle to notify for
    case notDetermined
    case denied
    case allowed
}

/// Posts banners through macOS Notification Center. Only works from the packaged .app.
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SystemNotifier()

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Call once at launch so banners also show while the popover is open.
    func activate() {
        center?.delegate = self
    }

    func permission() async -> NotificationPermission {
        guard let center else { return .unavailable }
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard let center, await permission() == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String, playSound: Bool) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
