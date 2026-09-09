import SwiftUI
import SwiftData

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(receipts) { receipt in
                    NavigationLink {
                        ReceiptDetailView(receipt: receipt)
                    } label: {
                        ReceiptRow(receipt: receipt, currencyCode: currencyCode)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No receipts",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Scanned receipts show up here.")
                    )
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                if !receipts.isEmpty {
                    EditButton()
                }
            }
            .refreshable {
                await AccountSync.pull(auth: auth, context: modelContext)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { receipts[$0] }
        Task {
            for receipt in targets {
                await AccountSync.delete(receipt, auth: auth, context: modelContext)
            }
        }
    }
}

private struct ReceiptRow: View {
    let receipt: Receipt
    let currencyCode: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            CategoryGlyph(category: receipt.category, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.merchant.isEmpty ? "Unknown merchant" : receipt.merchant)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                Text(receipt.date, format: .dateTime.month().day().year())
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Text(receipt.total, format: .currency(code: currencyCode))
                .font(.appCallout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ReceiptListView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
}
