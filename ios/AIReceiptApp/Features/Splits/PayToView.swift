import SwiftUI

/// How to pay someone back by Interac e-Transfer, when they've added it
/// (Account → Sharing & export).
struct PayToView: View {
    let payTo: ReceiptExtractionAPIClient.PayDetailsDTO
    let amount: Decimal
    let currency: String
    let name: String

    @State private var copied = false

    var body: some View {
        if let interac = payTo.interac {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Pay \(name) back: send \(amount.formatted(.currency(code: currency))) by Interac e-Transfer")
                    .font(.appCaption.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Button {
                    UIPasteboard.general.string = interac
                    copied = true
                } label: {
                    Label(copied ? "Copied" : interac, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .font(.appCaption)
            }
        }
    }
}
