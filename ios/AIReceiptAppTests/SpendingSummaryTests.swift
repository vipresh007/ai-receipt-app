import XCTest
@testable import AIReceiptApp

final class SpendingSummaryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// Fixed "now": 15 June 2026.
    private var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 6, day: 15).date!
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }

    private func receipt(_ total: Decimal, _ category: ExpenseCategory, on date: Date) -> Receipt {
        Receipt(merchant: "Test", date: date, total: total, category: category)
    }

    func testCurrentMonthTotalOnlyCountsThisMonth() {
        let receipts = [
            receipt(20, .groceries, on: date(year: 2026, month: 6, day: 2)),
            receipt(30, .restaurants, on: date(year: 2026, month: 6, day: 9)),
            receipt(99, .shopping, on: date(year: 2026, month: 5, day: 28)), // last month
        ]

        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: now)

        XCTAssertEqual(summary.currentMonthTotal, 50)
        XCTAssertEqual(summary.previousMonthTotal, 99)
    }

    func testCategoryBreakdownIsSortedDescending() {
        let receipts = [
            receipt(10, .groceries, on: date(year: 2026, month: 6, day: 1)),
            receipt(40, .restaurants, on: date(year: 2026, month: 6, day: 3)),
            receipt(25, .transport, on: date(year: 2026, month: 6, day: 5)),
        ]

        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: now)

        XCTAssertEqual(summary.currentMonthByCategory.map(\.category), [.restaurants, .transport, .groceries])
    }

    func testMonthOverMonthInsightFiresAboveFifteenPercent() {
        let receipts = [
            receipt(100, .restaurants, on: date(year: 2026, month: 5, day: 10)),
            receipt(130, .restaurants, on: date(year: 2026, month: 6, day: 10)), // +30%
        ]

        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: now)

        XCTAssertTrue(
            summary.insights.contains { $0.kind == .up && $0.message.contains("30% more on restaurants") },
            "Expected an 'up' insight, got: \(summary.insights.map(\.message))"
        )
    }

    func testAnchoringToAPastMonthSummarisesThatMonth() {
        let receipts = [
            receipt(40, .groceries, on: date(year: 2026, month: 4, day: 4)),
            receipt(70, .restaurants, on: date(year: 2026, month: 5, day: 9)),
            receipt(30, .groceries, on: date(year: 2026, month: 5, day: 20)),
            receipt(12, .transport, on: date(year: 2026, month: 6, day: 2)),
        ]

        // View May (one month before the test's fixed "now" of 15 June).
        let may = date(year: 2026, month: 5, day: 15)
        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: may)

        XCTAssertEqual(summary.currentMonthTotal, 100)      // May
        XCTAssertEqual(summary.previousMonthTotal, 40)      // April
        XCTAssertEqual(
            summary.currentMonthByCategory.map(\.category),
            [.restaurants, .groceries]
        )
    }

    func testMonthlyTrendIsZeroFilledOldestFirst() {
        let receipts = [
            receipt(40, .groceries, on: date(year: 2026, month: 4, day: 4)),
            receipt(100, .restaurants, on: date(year: 2026, month: 6, day: 9)),
        ]

        let trend = SpendingSummary.monthlyTrend(
            receipts: receipts, calendar: calendar, now: now, months: 4
        )

        // Apr, May, Jun (now is 15 Jun) -> plus one older = Mar..Jun
        XCTAssertEqual(trend.count, 4)
        XCTAssertEqual(trend.map(\.total), [0, 40, 0, 100])
        XCTAssertLessThan(trend[0].monthStart, trend[3].monthStart)
    }

    func testRisingStreakInsightAcrossThreeMonths() {
        let receipts = [
            receipt(50, .groceries, on: date(year: 2026, month: 4, day: 10)),
            receipt(70, .groceries, on: date(year: 2026, month: 5, day: 10)),
            receipt(90, .groceries, on: date(year: 2026, month: 6, day: 10)),
        ]

        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: now)

        XCTAssertTrue(
            summary.insights.contains { $0.kind == .streak },
            "Expected a streak insight, got: \(summary.insights.map(\.message))"
        )
    }
}
