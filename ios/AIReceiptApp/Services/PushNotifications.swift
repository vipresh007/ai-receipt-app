import UIKit
import UserNotifications

/// Push notifications for signed-in people: anything that lands in your
/// Activity ("Sam added Dinner, your share $20") also reaches your iPhone.
/// The device token goes to `POST /v1/devices`; the server sends through APNs
/// (`backend/app/services/push.py`).
@MainActor
enum PushNotifications {
    private static let tokenKey = "com.tally.push.token"
    /// Set by a tapped notification; RootView opens what it's about (or,
    /// without a target, the tab its link points at).
    static var onOpen: ((String, ActivityTarget?) -> Void)?

    static var token: String? { UserDefaults.standard.string(forKey: tokenKey) }

    /// Ask (once) and register. Called when a signed-in person opens Shared.
    static func enable() async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Re-register quietly on launch if already allowed (tokens can change).
    static func refresh() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func didRegister(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await upload() }
    }

    static weak var auth: AuthManager?

    static func upload() async {
        guard let auth, auth.isSignedIn, let token,
              let client = try? await Splits.client(auth) else { return }
        #if DEBUG
            let environment = "sandbox"
        #else
            let environment = "production"
        #endif
        try? await client.registerDevice(token: token, environment: environment)
    }

    /// Signing out: this phone stops getting the account's pushes.
    static func unregister(_ auth: AuthManager) async {
        guard let token, let client = try? await Splits.client(auth) else { return }
        try? await client.unregisterDevice(token: token)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotifications.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error)")
    }

    // Shown even while Tally is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let link = (info["link"] as? String) ?? (response.notification.request.identifier.hasPrefix("tally.reminder.") ? "receipts" : "")
        let target = ActivityTarget(push: info)
        await MainActor.run { PushNotifications.onOpen?(link, target) }
    }
}
