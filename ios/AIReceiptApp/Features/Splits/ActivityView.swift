import SwiftUI

/// Unread activity, shared by the tab badge and the bell (refreshed on
/// launch, on returning to the app, and after reading the feed).
@Observable
@MainActor
final class ActivityBadge {
    var unread = 0

    func refresh(_ auth: AuthManager) async {
        guard auth.isSignedIn, let client = try? await Splits.client(auth) else {
            unread = 0
            return
        }
        if let count = try? await client.unreadActivity() { unread = count }
    }
}

/// What the people you share with have added, changed, paid and said.
struct ActivityView: View {
    typealias API = ReceiptExtractionAPIClient

    @Environment(AuthManager.self) private var auth
    @Environment(ActivityBadge.self) private var badge
    @State private var items: [API.ActivityItemDTO] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "bell",
                    description: Text(errorMessage ?? "When someone adds an expense with you, records a payment or comments, it shows up here.")
                )
            } else {
                List(items) { item in
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Image(systemName: Self.icon(item.kind))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.read ? Theme.Palette.textTertiary : Theme.Palette.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                (item.read ? Theme.Palette.surface2 : Theme.Palette.accent.opacity(0.14)),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(item.actorName).fontWeight(.semibold) + Text(" \(item.text)"))
                                .font(.appCallout)
                                .foregroundStyle(Theme.Palette.text)
                            Text(item.date, format: .relative(presentation: .named))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        if !item.read {
                            Spacer(minLength: 0)
                            Circle().fill(Theme.Palette.accent).frame(width: 8, height: 8).padding(.top, 6)
                                .accessibilityLabel("New")
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Theme.Palette.surface)
                }
                .ledgerBackground()
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .liveRefresh { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let client = try await Splits.client(auth)
            let feed = try await client.activity()
            items = feed.items
            if feed.unread > 0 {
                try? await client.markActivityRead()
                badge.unread = 0
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "expense_added": "plus"
        case "expense_edited": "pencil"
        case "expense_deleted": "trash"
        case "comment": "text.bubble"
        case "payment": "banknote"
        case "reminder": "bell"
        case "joined": "person.badge.plus"
        case "repeated": "repeat"
        case "group_changed": "slider.horizontal.3"
        default: "bell"
        }
    }
}
