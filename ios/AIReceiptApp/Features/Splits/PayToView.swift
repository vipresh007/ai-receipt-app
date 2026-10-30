import SwiftUI

/// How to pay someone back, when they've said (Account → Sharing).
struct PayToView: View {
    let payTo: ReceiptExtractionAPIClient.PayDetailsDTO
    let amount: Decimal
    let currency: String
    let name: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Pay \(name) back")
                .font(.appCaption.weight(.medium))
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                if let handle = payTo.paypalMe, let url = paypalURL(handle) {
                    Link(destination: url) {
                        Label("PayPal", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                }
                if let interac = payTo.interac {
                    Button {
                        UIPasteboard.general.string = interac
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Interac: \(interac)", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.appCaption)
        }
    }

    private func paypalURL(_ handle: String) -> URL? {
        let formatted = String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
        let name = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        return URL(string: "https://paypal.me/\(name)/\(formatted)\(currency)")
    }
}
