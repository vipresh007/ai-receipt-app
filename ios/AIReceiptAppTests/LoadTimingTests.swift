import XCTest
@testable import AIReceiptApp

/// How long the work behind each screen takes with a heavy account: a year of
/// receipts with a busy month (100+), each with line items. Prints timings and
/// fails if one screen's worth of work goes over a frame budget.
final class LoadTimingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func heavyReceipts(perMonth: Int = 40, busyMonth: Int = 6, busy: Int = 120) -> [Receipt] {
        let stores = ["Loblaws", "Farm Boy", "Metro", "Costco", "Tim Hortons", "Uber", "Shell", "Indigo", "Shoppers", "Netflix"]
        let items = ["Oat milk 1L", "Sourdough loaf", "Bananas", "Greek yogurt 750g", "Coffee beans 340g",
                     "Eggs dozen", "Chicken thighs 1kg", "Spinach 312g", "Pasta 900g", "Cheddar 400g"]
        var out: [Receipt] = []
        for month in 1...12 {
            let count = month == busyMonth ? busy : perMonth
            for i in 0..<count {
                let day = (i % 28) + 1
                let date = DateComponents(calendar: calendar, year: 2026, month: month, day: day).date!
                let lines = (0..<6).map { j in
                    ReceiptLineItem(name: items[(i + j) % items.count], price: Decimal(300 + (i * 37 + j * 91 + month * 13) % 1500) / 100)
                }
                let total = lines.reduce(Decimal(0)) { $0 + $1.price }
                out.append(Receipt(merchant: stores[i % stores.count], date: date, total: total,
                                   category: ExpenseCategory.allCases[i % ExpenseCategory.allCases.count], items: lines))
            }
        }
        return out
    }

    private func ms(_ label: String, _ work: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "TIMING %@: %.1f ms", label, elapsed))
        return elapsed
    }

    func testScreensStayFastWithAHeavyYear() {
        let receipts = heavyReceipts()
        print("TIMING receipts:", receipts.count)
        let june = DateComponents(calendar: calendar, year: 2026, month: 6, day: 30).date!

        let summary = ms("SpendingSummary x1") { _ = SpendingSummary(receipts: receipts, calendar: calendar, now: june, today: june) }
        let prices = ms("PriceTracker.items x1") { _ = PriceTracker.items(in: receipts) }
        let recurring = ms("RecurringDetector.find x1") { _ = RecurringDetector.find(in: receipts, calendar: calendar) }
        let trend = ms("periodTrend x1") {
            _ = SpendingSummary.periodTrend(receipts: receipts, calendar: calendar, now: june, granularity: .month, periods: 12)
        }
        // What a redraw costs once those are cached: the fingerprint check.
        let check = ms("ReceiptsSignature x8") { for _ in 0..<8 { _ = ReceiptsSignature.of(receipts) } }
        print(String(format: "TIMING trend %.1f ms, recurring %.1f ms, prices %.1f ms", trend, recurring, prices))
        XCTAssertLessThan(check, 16)
        XCTAssertLessThan(summary, 50)
        XCTAssertLessThan(prices, 50)
        XCTAssertLessThan(recurring, 50)
    }
}

extension LoadTimingTests {
    func testRepeatReadsAreFreeUntilReceiptsChange() {
        let receipts = heavyReceiptsForReuse()
        _ = PriceTracker.items(in: receipts)
        var again: [TrackedItem] = []
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<8 { again = PriceTracker.items(in: receipts) }
        let eight = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "TIMING PriceTracker.items x8 (cached): %.1f ms", eight))
        XCTAssertFalse(again.isEmpty)
        XCTAssertLessThan(eight, 16)

        // A change (one receipt's total) is seen at once.
        receipts[0].total += 1
        let start2 = CFAbsoluteTimeGetCurrent()
        _ = PriceTracker.items(in: receipts)
        print(String(format: "TIMING PriceTracker.items after a change: %.1f ms", (CFAbsoluteTimeGetCurrent() - start2) * 1000))
    }

    private func heavyReceiptsForReuse() -> [Receipt] {
        let calendar = Calendar(identifier: .gregorian)
        return (0..<560).map { i in
            let date = DateComponents(calendar: calendar, year: 2026, month: (i % 12) + 1, day: (i % 28) + 1).date!
            let lines = (0..<6).map { j in ReceiptLineItem(name: "Item \((i + j) % 10)", price: Decimal(200 + (i * 7 + j) % 900) / 100) }
            return Receipt(merchant: "Store \(i % 9)", date: date, total: lines.reduce(0) { $0 + $1.price }, items: lines)
        }
    }
}
