import Foundation
import SwiftData
import UserNotifications

/// Local reminders for return windows and warranties — no push server needed.
/// Rebuilt from all receipts whenever the app comes forward or a date
/// changes: 3 days before the last day to return (and the morning of), and
/// 30 days before a warranty ends. The server emails the same reminders to
/// web users (`backend/app/services/reminders.py`).
enum ReturnReminders {
    private static let prefix = "tally.reminder."
    private static let hour = 10  // in the morning, local time

    /// Ask once, the first time someone sets a date.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    @MainActor
    static func sync(_ context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        // Account → Notifications → Returns & warranties → Push.
        let wanted = UserDefaults.standard.object(forKey: NotificationSettingsView.localReturnsKey) as? Bool ?? true
        guard wanted else { return }

        let receipts = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        var requests: [UNNotificationRequest] = []
        let now = Date.now
        for receipt in receipts {
            let store = receipt.merchant.isEmpty ? "a receipt" : receipt.merchant
            let key = receipt.remoteID ?? String(receipt.createdAt.timeIntervalSince1970)
            if let last = receipt.returnBy {
                if let early = at(Calendar.current.date(byAdding: .day, value: -3, to: last)), early > now {
                    requests.append(request("\(prefix)return3.\(key)", "Return window closing", "You have until \(last.formatted(.dateTime.weekday(.wide).month().day())) to return your \(store) purchase.", early))
                }
                if let day = at(last), day > now {
                    requests.append(request("\(prefix)return0.\(key)", "Last day to return", "Today's the last day to return your \(store) purchase.", day))
                }
            }
            if let end = receipt.warrantyUntil,
               let early = at(Calendar.current.date(byAdding: .day, value: -30, to: end)), early > now {
                requests.append(request("\(prefix)warranty.\(key)", "Warranty ending soon", "The warranty on your \(store) purchase ends \(end.formatted(.dateTime.month().day().year())).", early))
            }
        }
        // iOS keeps at most 64 pending; the soonest matter most.
        for r in requests.sorted(by: { fireDate($0) < fireDate($1) }).prefix(60) {
            try? await center.add(r)
        }
    }

    private static func at(_ day: Date?) -> Date? {
        guard let day else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func request(_ id: String, _ title: String, _ body: String, _ date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    private static func fireDate(_ request: UNNotificationRequest) -> Date {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
}
