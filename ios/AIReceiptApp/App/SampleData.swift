#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample receipts for previews, simulator checks and App Store
/// screenshots. Runs only when launched with `-seedSampleReceipts` and only
/// into an empty store, so it never touches real data.
enum SampleData {
    static let launchArgument = "-seedSampleReceipts"

    /// `-demoAccount`: act signed in as "Alex" against a local demo API on
    /// 127.0.0.1:8765 (made-up people and groups), for Shared screenshots.
    static let demoAccount = ProcessInfo.processInfo.arguments.contains("-demoAccount")
    static let demoAPI = URL(string: "http://127.0.0.1:8765")!

    /// `-seedBusyJune`: add 100 June receipts with line items (load testing).
    @MainActor
    static func seedBusyJuneIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedBusyJune") else { return }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        let juneStart = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        let juneEnd = calendar.date(byAdding: .month, value: 1, to: juneStart)!
        let existing = (try? context.fetchCount(FetchDescriptor<Receipt>(
            predicate: #Predicate { $0.date >= juneStart && $0.date < juneEnd }
        ))) ?? 0
        guard existing < 100 else { return }
        let stores: [(String, ExpenseCategory)] = [
            ("Loblaws", .groceries), ("Farm Boy", .groceries), ("Metro", .groceries), ("Costco", .groceries),
            ("Tim Hortons", .restaurants), ("Pizzeria Libretto", .restaurants), ("Uber", .transport),
            ("Shell", .transport), ("Indigo", .shopping), ("Shoppers Drug Mart", .health),
        ]
        let names = ["Oat milk 1L", "Sourdough loaf", "Bananas", "Greek yogurt 750g", "Coffee beans 340g",
                     "Eggs dozen", "Chicken thighs 1kg", "Spinach 312g", "Pasta 900g", "Cheddar 400g"]
        for i in 0..<100 {
            let (store, category) = stores[i % stores.count]
            let day = calendar.date(byAdding: .day, value: i % 30, to: juneStart)!
            let lines = (0..<(3 + i % 5)).map { j in
                ReceiptLineItem(name: names[(i + j) % names.count], price: Decimal(250 + (i * 37 + j * 91) % 1400) / 100)
            }
            let total = lines.reduce(Decimal(0)) { $0 + $1.price }
            context.insert(Receipt(merchant: store, date: day, total: total, category: category, items: lines))
        }
        try? context.save()
    }

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
        // The same groceries every month, slowly getting pricier, so Prices
        // and the "was $3.99" notes have something to show.
        func groceries(_ monthsAgo: Int) -> [ReceiptLineItem] {
            let step = Decimal(5 - monthsAgo)  // 0 five months ago … 5 now
            return [
                ReceiptLineItem(name: "Oat milk 1L", price: 3.99 + step * 0.10),
                ReceiptLineItem(name: "Sourdough loaf", price: monthsAgo > 2 ? 5.99 : 6.50),
                ReceiptLineItem(name: "Coffee beans 340g", price: monthsAgo > 1 ? 13.99 : 14.99),
                ReceiptLineItem(name: "Bananas", price: 1.69),
                ReceiptLineItem(name: "Greek yogurt 750g", price: monthsAgo == 3 ? 4.99 : 5.99),
            ]
        }
        for (monthsAgo, d, merchant, total, category) in rows {
            context.insert(
                Receipt(
                    merchant: merchant, date: day(monthsAgo, d), total: total, category: category,
                    items: category == .groceries ? groceries(monthsAgo) : []
                )
            )
        }
        try? context.save()
    }
}
#endif
