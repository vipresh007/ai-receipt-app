import SwiftUI
import SwiftData

/// One calendar month's worth of receipts, newest month first — mirrors the
/// grouping on web's `/receipts` page.
private struct MonthGroup: Identifiable {
    let id: Date
    let label: String
    let items: [Receipt]
    let total: Decimal
}

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth
    @Environment(\.calendar) private var calendar
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var monthGroups: [MonthGroup] {
        var buckets: [Date: [Receipt]] = [:]
        for receipt in receipts {
            let start = calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
            buckets[start, default: []].append(receipt)
        }
        return buckets.keys.sorted(by: >).map { start in
            let items = buckets[start] ?? []
            return MonthGroup(
                id: start,
                label: start.formatted(.dateTime.month(.wide).year()),
                items: items,
                total: items.reduce(Decimal(0)) { $0 + $1.total }
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(monthGroups) { group in
                    Section {
                        ForEach(group.items) { receipt in
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt)
                            } label: {
                                ReceiptRow(receipt: receipt, currencyCode: currencyCode)
                            }
                        }
                        .onDelete { delete(group.items, at: $0) }
                    } header: {
                        HStack {
                            Text(group.label)
                            Spacer()
                            Text(group.total, format: .currency(code: currencyCode))
                                .monospacedDigit()
                        }
                        .font(.appCaption.weight(.medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .textCase(nil)
                    }
                }
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

    private func delete(_ items: [Receipt], at offsets: IndexSet) {
        let targets = offsets.map { items[$0] }
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
