import Foundation
import SwiftUI

/// What you pay for the things you buy again and again, from your own line
/// items: "Oat milk 1L is $4.49 now, up from $3.99 in June."
///
/// Items match by name across receipts and stores (`PriceTracker.key`, the
/// same rule as the backend's `services/prices.py` and the web's
/// `lib/prices.ts`). A line's price is its total, so the unit price is
/// price ÷ quantity.
struct TrackedItem: Identifiable, Hashable {
    struct Purchase: Hashable {
        let date: Date
        let merchant: String
        let unitPrice: Decimal
    }

    let key: String
    /// The name as it was last written on a receipt.
    let name: String
    /// Oldest first.
    let purchases: [Purchase]

    var id: String { key }
    var latest: Purchase { purchases[purchases.count - 1] }

    /// The purchase before the latest one at a different price, if the price
    /// has ever moved.
    var previous: Purchase? {
        purchases.dropLast().last { $0.unitPrice != latest.unitPrice }
    }

    /// Latest vs `previous`, e.g. 0.125 for +12.5%.
    var change: Double? {
        guard let previous, previous.unitPrice > 0 else { return nil }
        return NSDecimalNumber(decimal: (latest.unitPrice - previous.unitPrice) / previous.unitPrice).doubleValue
    }
}

enum PriceTracker {
    /// Lowercased, punctuation dropped (but "1.2kg" kept), spaces collapsed.
    static func key(_ name: String) -> String {
        let lowered = name.lowercased()
        let kept = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "%" ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Items bought on at least two different receipts, most recently bought first.
    static func items(in receipts: [Receipt]) -> [TrackedItem] {
        var buckets: [String: [(TrackedItem.Purchase, String)]] = [:]
        for receipt in receipts {
            var seen: Set<String> = []
            for item in receipt.items where item.price > 0 {
                let key = key(item.name)
                // One entry per receipt per item; the key must say something.
                guard key.count >= 3, !seen.contains(key) else { continue }
                seen.insert(key)
                let unit = item.price / Decimal(max(item.quantity, 1))
                buckets[key, default: []].append(
                    (.init(date: receipt.date, merchant: receipt.merchant, unitPrice: unit.rounded(2)), item.name)
                )
            }
        }
        return buckets.compactMap { key, rows in
            guard rows.count >= 2 else { return nil }
            let sorted = rows.sorted { $0.0.date < $1.0.date }
            return TrackedItem(key: key, name: sorted[sorted.count - 1].1, purchases: sorted.map(\.0))
        }
        .sorted { $0.latest.date > $1.latest.date }
    }

    /// For a receipt's item: the last time you bought it before this receipt,
    /// when the price was different.
    static func earlier(for item: ReceiptLineItem, on receipt: Receipt, in tracked: [TrackedItem]) -> TrackedItem.Purchase? {
        let key = key(item.name)
        guard item.price > 0, let found = tracked.first(where: { $0.key == key }) else { return nil }
        let unit = (item.price / Decimal(max(item.quantity, 1))).rounded(2)
        return found.purchases.last { $0.date < receipt.date && $0.unitPrice != unit }
    }

    /// The biggest price rise among items last bought within `days`, if any
    /// rose by 5% or more.
    static func biggestRise(in tracked: [TrackedItem], within days: Int = 45, now: Date = .now) -> TrackedItem? {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return tracked
            .filter { $0.latest.date >= since && ($0.change ?? 0) >= 0.05 }
            .max { ($0.change ?? 0) < ($1.change ?? 0) }
    }
}

extension Decimal {
    func rounded(_ places: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, places, .bankers)
        return result
    }
}

/// "↑ was $3.99 at Loblaws, Jun 12" under a receipt line.
struct PriceWasNote: View {
    let before: TrackedItem.Purchase
    let now: ReceiptLineItem
    let currencyCode: String

    private var unit: Decimal { now.price / Decimal(max(now.quantity, 1)) }
    private var up: Bool { unit > before.unitPrice }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text("was \(before.unitPrice.formatted(.currency(code: currencyCode))) at \(before.merchant), \(before.date.formatted(.dateTime.month(.abbreviated).day()))")
        }
        .font(.appCaption)
        .foregroundStyle(up ? Theme.Palette.danger : Theme.Palette.success)
    }
}
