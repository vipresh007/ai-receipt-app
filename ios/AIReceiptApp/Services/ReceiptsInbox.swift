import SwiftUI

/// Forwarding e-receipts by email (backend/app/services/inbox.py): where
/// they go, and the one-time tip after someone adds an e-receipt by hand.
@MainActor
enum ReceiptsInbox {
    /// The shared mailbox; forwarding works from the account's own email.
    static let general = "receipts@dataeaver.ca"

    private static let addressKey = "receiptsInbox.address"
    private static let tipKey = "receiptsInbox.tipShown"

    /// Known once signed in and the server's mailbox is set up.
    static var address: String? { UserDefaults.standard.string(forKey: addressKey) }

    static var tipShown: Bool {
        get { UserDefaults.standard.bool(forKey: tipKey) }
        set { UserDefaults.standard.set(newValue, forKey: tipKey) }
    }

    /// Ask the account where to forward (signed out: nothing).
    static func refresh(_ auth: AuthManager) async {
        guard auth.isSignedIn else {
            UserDefaults.standard.removeObject(forKey: addressKey)
            return
        }
        guard let me = try? await Splits.client(auth).me() else { return }
        UserDefaults.standard.set(me.receiptsEmail, forKey: addressKey)
    }

    /// Stores whose receipts usually arrive by email.
    static func looksOnline(_ merchant: String) -> Bool {
        let key = DuplicateFinder.storeKey(merchant)
        return ["uber", "lyft", "doordash", "skipthedishes", "instacart", "amazon", "netflix", "spotify",
                "airbnb", "expedia", "booking", "apple", "google", "paypal", "shopify", "etsy", "ebay"]
            .contains { key.hasPrefix($0) }
    }
}

/// "Got an e-receipt? Forward it to receipts@dataeaver.ca" — tap to copy.
struct ForwardHint: View {
    let address: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = address
            withAnimation(Theme.Motion.base) { copied = true }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "envelope")
                (Text("Got an e-receipt? Forward it to ") + Text(address).fontWeight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(Theme.Palette.accent)
            }
            .font(.appCaption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied \(address)" : "Forward e-receipts to \(address). Tap to copy.")
    }
}
