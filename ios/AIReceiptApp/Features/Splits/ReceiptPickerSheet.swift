import SwiftUI
import SwiftData

/// Pick one of your receipts to split (synced, not split yet), newest first.
struct ReceiptPickerSheet: View {
    let onPick: (Receipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var query = ""

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    private var choices: [Receipt] {
        receipts.filter { r in
            r.remoteID != nil && r.splitID == nil
                && (query.isEmpty || r.merchant.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if choices.isEmpty {
                    Text(query.isEmpty ? "No receipts to split yet. Scan one first." : "No receipts match.")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ForEach(choices) { receipt in
                    Button {
                        onPick(receipt)
                        dismiss()
                    } label: {
                        HStack(spacing: Theme.Space.md) {
                            CategoryGlyph(category: receipt.category, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(receipt.merchant.isEmpty ? "Receipt" : receipt.merchant)
                                    .font(.appCallout)
                                    .foregroundStyle(Theme.Palette.text)
                                Text(receipt.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer()
                            Text(receipt.total, format: .currency(code: currencyCode))
                                .font(.appMoney)
                                .foregroundStyle(Theme.Palette.text)
                        }
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
            .ledgerBackground()
            .searchable(text: $query, prompt: "Store")
            .navigationTitle("Pick a receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
