import SwiftUI

/// Everything you buy more than once, what it costs now, and how that moved.
struct PriceListView: View {
    let items: [TrackedItem]
    let currencyCode: String

    @State private var search = ""

    private var shown: [TrackedItem] {
        let query = PriceTracker.key(search)
        return query.isEmpty ? items : items.filter { $0.key.contains(query) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { item in
                    NavigationLink {
                        PriceHistoryView(item: item, currencyCode: currencyCode)
                    } label: {
                        PriceRow(item: item, currencyCode: currencyCode)
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            } footer: {
                Text("Items you've bought on two or more receipts, matched by name across stores. Prices are per item.")
            }
        }
        .ledgerBackground()
        .navigationTitle("Prices")
        .searchable(text: $search, prompt: "Find an item")
    }
}

struct PriceRow: View {
    let item: TrackedItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text("\(item.purchases.count) times · last \(item.latest.merchant), \(item.latest.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.latest.unitPrice, format: .currency(code: currencyCode))
                    .font(.appMoney)
                    .foregroundStyle(Theme.Palette.text)
                if let change = item.change {
                    PriceChangeLabel(change: change)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PriceChangeLabel: View {
    let change: Double

    var body: some View {
        let up = change > 0
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text("\(Int((abs(change) * 100).rounded()))%")
        }
        .font(.appCaption.weight(.medium))
        .foregroundStyle(up ? Theme.Palette.danger : Theme.Palette.success)
    }
}

/// Every time you bought one item: when, where, and what it cost.
struct PriceHistoryView: View {
    let item: TrackedItem
    let currencyCode: String

    private var cheapest: TrackedItem.Purchase? { item.purchases.min { $0.unitPrice < $1.unitPrice } }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now").font(.appCaption).foregroundStyle(Theme.Palette.textTertiary)
                        Text(item.latest.unitPrice, format: .currency(code: currencyCode)).font(.appMoney)
                    }
                    Spacer()
                    if let cheapest, cheapest.unitPrice < item.latest.unitPrice {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Cheapest").font(.appCaption).foregroundStyle(Theme.Palette.textTertiary)
                            Text("\(cheapest.unitPrice.formatted(.currency(code: currencyCode))) at \(cheapest.merchant)")
                                .font(.appCallout)
                                .foregroundStyle(Theme.Palette.success)
                        }
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
            Section("Bought") {
                ForEach(Array(item.purchases.reversed().enumerated()), id: \.offset) { _, purchase in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(purchase.merchant).font(.appCallout)
                            Text(purchase.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        Text(purchase.unitPrice, format: .currency(code: currencyCode)).font(.appMoney)
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
