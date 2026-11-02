import SwiftUI
import UserNotifications

/// Which notifications you get, kind by kind, as a push and/or an email.
/// Everything still shows under Activity; this only decides what reaches you.
struct NotificationSettingsView: View {
    typealias API = ReceiptExtractionAPIClient

    struct Kind: Identifiable {
        let id: String
        let title: String
        let example: String
        let email: Bool
    }

    static let kinds: [Kind] = [
        Kind(id: "expenses", title: "Shared expenses", example: "Sam added Dinner, your share $20", email: true),
        Kind(id: "payments", title: "Payments", example: "Sam paid you $40", email: true),
        Kind(id: "reminders", title: "Reminders to pay", example: "Sam reminded you about $25", email: true),
        Kind(id: "comments", title: "Comments", example: "Sam commented on Dinner", email: false),
        Kind(id: "returns", title: "Returns & warranties", example: "Last day to return your Best Buy purchase", email: true),
        Kind(id: "emailed", title: "Receipts you email in", example: "Added Uber $23.40 from your email", email: false),
    ]

    /// Local return/warranty reminders follow "returns.push" (ReturnReminders).
    static let localReturnsKey = "notify.returns.push"

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var me: API.MeDTO?
    @State private var prefs: [String: Bool] = [:]
    @State private var emails = true
    @State private var systemOff = false
    @State private var error: String?

    var body: some View {
        Form {
            if systemOff {
                Section {
                    Button("Notifications are off for Tally in iOS Settings. Turn them on") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.appCallout)
                }
                .listRowBackground(Theme.Palette.surface)
            }

            Section {
                ForEach(Self.kinds) { kind in
                    toggleRow(kind, key: "\(kind.id).push")
                }
            } header: {
                header("On this iPhone")
            }
            .listRowBackground(Theme.Palette.surface)

            Section {
                Toggle(isOn: Binding(get: { emails }, set: { on in
                    emails = on
                    Task { await save(.init(emailNotifications: on)) }
                })) {
                    Text("Send me emails").font(.appCallout.weight(.medium))
                }
                if emails {
                    ForEach(Self.kinds.filter(\.email)) { kind in
                        toggleRow(kind, key: "\(kind.id).email", example: false)
                    }
                }
            } header: {
                header("By email")
            } footer: {
                Text("At most one email every 10 minutes. Everything also shows under Activity.")
                    .font(.appCaption)
            }
            .listRowBackground(Theme.Palette.surface)

            if let error {
                Text(error).font(.appCaption).foregroundStyle(Theme.Palette.danger)
                    .listRowBackground(Color.clear)
            }
        }
        .ledgerBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased()).font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
    }

    private func toggleRow(_ kind: Kind, key: String, example: Bool = true) -> some View {
        Toggle(isOn: binding(key)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.appCallout)
                if example {
                    Text(kind.example)
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { prefs[key] ?? true },
            set: { on in
                prefs[key] = on
                if key == "returns.push" {
                    UserDefaults.standard.set(on, forKey: Self.localReturnsKey)
                    Task { await ReturnReminders.sync(modelContext) }
                }
                Task { await save(.init(notifyPrefs: [key: on])) }
            }
        )
    }

    private func load() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        systemOff = status == .denied
        guard let loaded = try? await Splits.client(auth).me() else { return }
        me = loaded
        emails = loaded.emailNotifications
        prefs = loaded.notifyPrefs ?? [:]
        UserDefaults.standard.set(prefs["returns.push"] ?? true, forKey: Self.localReturnsKey)
    }

    private func save(_ body: API.MeSettingsWrite) async {
        do {
            let updated = try await Splits.client(auth).updateMe(body)
            me = updated
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
