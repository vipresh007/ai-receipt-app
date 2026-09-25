import XCTest
@testable import AIReceiptApp

final class GranularityTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }

    // MARK: - interval(containing:)

    func testQuarterIntervalForSeptemberIsJulyThroughSeptember() {
        let interval = Granularity.quarter.interval(containing: date(2026, 9, 15), calendar: calendar)!
        XCTAssertEqual(interval.start, date(2026, 7, 1))
        XCTAssertEqual(interval.end, date(2026, 10, 1))
    }

    func testQuarterIntervalForFebruaryIsJanuaryThroughMarch() {
        let interval = Granularity.quarter.interval(containing: date(2026, 2, 10), calendar: calendar)!
        XCTAssertEqual(interval.start, date(2026, 1, 1))
        XCTAssertEqual(interval.end, date(2026, 4, 1))
    }

    func testYearIntervalSpansTheFullCalendarYear() {
        let interval = Granularity.year.interval(containing: date(2026, 6, 1), calendar: calendar)!
        XCTAssertEqual(interval.start, date(2026, 1, 1))
        XCTAssertEqual(interval.end, date(2027, 1, 1))
    }

    // MARK: - shift

    func testShiftingAQuarterBackFromQ3LandsInsideQ2() {
        let shifted = Granularity.quarter.shift(date(2026, 9, 15), by: -1, calendar: calendar)
        let interval = Granularity.quarter.interval(containing: shifted, calendar: calendar)!
        XCTAssertEqual(interval.start, date(2026, 4, 1))
        XCTAssertEqual(interval.end, date(2026, 7, 1))
    }

    func testShiftingAYearBackCrossesTheYearBoundary() {
        let shifted = Granularity.year.shift(date(2026, 3, 1), by: -1, calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: shifted), 2025)
    }

    func testShiftingAQuarterBackAcrossAYearBoundary() {
        let shifted = Granularity.quarter.shift(date(2026, 1, 15), by: -1, calendar: calendar)
        let interval = Granularity.quarter.interval(containing: shifted, calendar: calendar)!
        XCTAssertEqual(interval.start, date(2025, 10, 1))
        XCTAssertEqual(interval.end, date(2026, 1, 1))
    }

    // MARK: - key (period equality)

    func testJulyAndSeptemberShareTheSameQuarterKey() {
        XCTAssertEqual(
            Granularity.quarter.key(for: date(2026, 7, 1), calendar: calendar),
            Granularity.quarter.key(for: date(2026, 9, 20), calendar: calendar)
        )
    }

    func testQ2AndQ3KeysDiffer() {
        XCTAssertNotEqual(
            Granularity.quarter.key(for: date(2026, 6, 1), calendar: calendar),
            Granularity.quarter.key(for: date(2026, 7, 1), calendar: calendar)
        )
    }

    // MARK: - periodTrend

    func testPeriodTrendQuarterSumsMonthsWithinEachQuarter() {
        let receipts = [
            Receipt(merchant: "A", date: date(2026, 7, 5), total: 10, category: .other),
            Receipt(merchant: "A", date: date(2026, 8, 5), total: 20, category: .other),
            Receipt(merchant: "A", date: date(2026, 9, 5), total: 30, category: .other),
        ]
        let points = SpendingSummary.periodTrend(
            receipts: receipts, calendar: calendar, now: date(2026, 9, 15), granularity: .quarter, periods: 1
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.total, 60)
    }

    func testPeriodTrendIsOldestFirst() {
        let points = SpendingSummary.periodTrend(
            receipts: [], calendar: calendar, now: date(2026, 9, 15), granularity: .month, periods: 3
        )
        XCTAssertEqual(points.map(\.label), ["Jul", "Aug", "Sep"])
    }

    // MARK: - SpendingSummary with a non-month granularity

    func testSpendingSummaryWithNoReceiptsHasNoInsights() {
        let summary = SpendingSummary(receipts: [], calendar: calendar, now: date(2026, 9, 15), granularity: .quarter)
        XCTAssertTrue(summary.insights.isEmpty)
    }

    func testSpendingSummaryQuarterComparesWithThePreviousQuarter() {
        let receipts = [
            Receipt(merchant: "A", date: date(2026, 5, 10), total: 100, category: .groceries), // Q2
            Receipt(merchant: "B", date: date(2026, 8, 10), total: 150, category: .groceries), // Q3
        ]
        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: date(2026, 9, 15), granularity: .quarter)
        XCTAssertTrue(
            summary.insights.contains { $0.kind == .up && $0.message.contains("50% more on groceries than the quarter before") },
            "Got: \(summary.insights.map(\.message))"
        )
    }

    func testSpendingSummaryDefaultGranularityStillMatchesMonthBehavior() {
        let receipts = [Receipt(merchant: "A", date: date(2026, 9, 5), total: 42, category: .other)]
        let summary = SpendingSummary(receipts: receipts, calendar: calendar, now: date(2026, 9, 15))
        XCTAssertEqual(summary.currentMonthTotal, 42)
    }
}
