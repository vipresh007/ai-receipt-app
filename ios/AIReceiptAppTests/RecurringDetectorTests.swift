import XCTest
@testable import AIReceiptApp

final class RecurringDetectorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }

    private func receipt(
        _ merchant: String,
        _ total: Decimal,
        _ date: Date,
        category: ExpenseCategory = .entertainment
    ) -> Receipt {
        Receipt(merchant: merchant, date: date, total: total, category: category)
    }

    func testNoReceiptsNoRecurring() {
        XCTAssertTrue(RecurringDetector.find(in: [], calendar: calendar).isEmpty)
    }

    func testSameMerchantTwoMonthsSameAmountIsRecurring() {
        let receipts = [
            receipt("Netflix", 15.49, date(year: 2026, month: 7, day: 1)),
            receipt("Netflix", 15.49, date(year: 2026, month: 8, day: 1)),
        ]
        let groups = RecurringDetector.find(in: receipts, calendar: calendar)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.merchant, "Netflix")
        XCTAssertEqual(groups.first?.occurrences, 2)
        XCTAssertEqual(groups.first?.averageAmount, 15.49)
    }

    func testOneOffPurchaseIsNotRecurring() {
        let receipts = [receipt("Corner Store", 12.00, date(year: 2026, month: 9, day: 1))]
        XCTAssertTrue(RecurringDetector.find(in: receipts, calendar: calendar).isEmpty)
    }

    func testSameMonthTwiceIsNotRecurring() {
        let receipts = [
            receipt("Corner Store", 12.00, date(year: 2026, month: 9, day: 1)),
            receipt("Corner Store", 12.00, date(year: 2026, month: 9, day: 15)),
        ]
        XCTAssertTrue(RecurringDetector.find(in: receipts, calendar: calendar).isEmpty)
    }

    func testWildlyDifferentAmountsAreNotRecurring() {
        let receipts = [
            receipt("Amazon", 10.00, date(year: 2026, month: 7, day: 1)),
            receipt("Amazon", 300.00, date(year: 2026, month: 8, day: 1)),
        ]
        XCTAssertTrue(RecurringDetector.find(in: receipts, calendar: calendar).isEmpty)
    }

    func testMerchantMatchingIsCaseInsensitive() {
        let receipts = [
            receipt("spotify", 9.99, date(year: 2026, month: 7, day: 1)),
            receipt("Spotify", 9.99, date(year: 2026, month: 8, day: 1)),
        ]
        let groups = RecurringDetector.find(in: receipts, calendar: calendar)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.occurrences, 2)
    }

    func testResultsAreSortedByMostRecentFirst() {
        let receipts = [
            receipt("Netflix", 15.49, date(year: 2026, month: 6, day: 1)),
            receipt("Netflix", 15.49, date(year: 2026, month: 7, day: 1)),
            receipt("Spotify", 9.99, date(year: 2026, month: 8, day: 1)),
            receipt("Spotify", 9.99, date(year: 2026, month: 9, day: 1)),
        ]
        let groups = RecurringDetector.find(in: receipts, calendar: calendar)
        XCTAssertEqual(groups.map(\.merchant), ["Spotify", "Netflix"])
    }
}
