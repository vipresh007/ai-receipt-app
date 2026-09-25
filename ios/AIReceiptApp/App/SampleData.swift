#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample receipts for previews, simulator checks and App Store
/// screenshots. Runs only when launched with `-seedSampleReceipts` and only
/// into an empty store, so it never touches real data.
enum SampleData {
    static let launchArgument = "-seedSampleReceipts"

    @MainActor
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Receipt>())) ?? 0
        guard existing == 0 else { return }

        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        func day(_ monthsAgo: Int, _ day: Int) -> Date {
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: thisMonth) ?? thisMonth
            let clamped = monthsAgo == 0 ? min(day, calendar.component(.day, from: .now)) : day
            return calendar.date(byAdding: .day, value: clamped - 1, to: month) ?? month
        }

        // (monthsAgo, day, merchant, total, category) — six months of history
        // with a rising groceries line and a restaurants dip, so every
        // insight type has something to say.
        let rows: [(Int, Int, String, Decimal, ExpenseCategory)] = [
            (5, 4, "Loblaws", 131.40, .groceries), (5, 10, "Presto", 40, .transport),
            (5, 18, "Bluebird Cafe", 31.20, .restaurants), (5, 24, "Enbridge Gas", 94.10, .utilities),
            (4, 3, "Farm Boy", 142.10, .groceries), (4, 9, "Presto", 40, .transport),
            (4, 14, "Bluebird Cafe", 38.45, .restaurants), (4, 22, "Enbridge Gas", 88.20, .utilities),
            (3, 2, "Loblaws", 168.30, .groceries), (3, 11, "The Keg", 96.75, .restaurants),
            (3, 17, "Presto", 40, .transport), (3, 25, "Indigo", 54.99, .shopping),
            (2, 4, "Farm Boy", 181.64, .groceries), (2, 12, "Pizzeria Libretto", 64.30, .restaurants),
            (2, 19, "Cineplex", 32.50, .entertainment), (2, 27, "Enbridge Gas", 91.40, .utilities),
            (1, 3, "Loblaws", 196.22, .groceries), (1, 8, "Bluebird Cafe", 22.15, .restaurants),
            (1, 15, "Presto", 40, .transport), (1, 21, "Hudson's Bay", 119.99, .shopping),
            (1, 28, "Shoppers Drug Mart", 27.48, .health),
            (0, 2, "Farm Boy", 124.87, .groceries), (0, 5, "Bluebird Cafe", 8.43, .restaurants),
            (0, 9, "Presto", 40, .transport), (0, 12, "Loblaws", 101.35, .groceries),
            (0, 16, "Enbridge Gas", 86.90, .utilities), (0, 20, "Sushi Kaji", 58.10, .restaurants),
        ]
        for (monthsAgo, d, merchant, total, category) in rows {
            context.insert(Receipt(merchant: merchant, date: day(monthsAgo, d), total: total, category: category))
        }
        try? context.save()
    }
}
#endif
