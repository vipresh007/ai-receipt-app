import SwiftUI
import SwiftData

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
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
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(receipts[index])
        }
    }
}

private struct ReceiptRow: View {
    let receipt: Receipt
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: receipt.category.systemImage)
                .foregroundStyle(receipt.category.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant).fontWeight(.medium)
                Text(receipt.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(receipt.total, format: .currency(code: currencyCode))
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ReceiptListView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
