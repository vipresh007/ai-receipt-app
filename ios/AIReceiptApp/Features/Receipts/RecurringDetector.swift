import Foundation

/// A merchant that looks like a recurring charge — appears in at least two
/// different months at roughly the same amount. Heuristic, not a bank feed.
/// Mirrors `backend/app/services/recurring.py` so both surfaces agree.
struct RecurringGroup: Identifiable {
    let merchant: String
    let category: ExpenseCategory
    let averageAmount: Decimal
    let occurrences: Int
    let lastPurchased: Date

    var id: String { merchant.lowercased() }
}

enum RecurringDetector {
    private static let tolerance = Decimal(string: "0.15")!
    private static let minOccurrences = 2

    /// Groups by normalized merchant name, keeping groups that span at least
    /// `minOccurrences` distinct calendar months with amounts close enough
    /// together to plausibly be the same recurring charge.
    static func find(in receipts: [Receipt], calendar: Calendar = .current) -> [RecurringGroup] {
        var byMerchant: [String: [Receipt]] = [:]
        for receipt in receipts {
            let key = receipt.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            byMerchant[key, default: []].append(receipt)
        }

        var groups: [RecurringGroup] = []
        for items in byMerchant.values {
            let distinctMonths = Set(items.map { calendar.dateComponents([.year, .month], from: $0.date) })
            guard distinctMonths.count >= minOccurrences else { continue }

            let total = items.reduce(Decimal(0)) { $0 + $1.total }
            let average = total / Decimal(items.count)
            guard average > 0 else { continue }
            guard items.allSatisfy({ abs($0.total - average) <= average * tolerance }) else { continue }

            guard let latest = items.max(by: { $0.date < $1.date }) else { continue }
            groups.append(
                RecurringGroup(
                    merchant: latest.merchant,
                    category: latest.category,
                    averageAmount: average,
                    occurrences: items.count,
                    lastPurchased: latest.date
                )
            )
        }
        return groups.sorted { $0.lastPurchased > $1.lastPurchased }
    }
}
