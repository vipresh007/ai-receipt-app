import XCTest
@testable import AIReceiptApp

/// Same rules as backend/tests/test_duplicates.py.
final class DuplicateFinderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, hour: Int = 9) -> Date {
        DateComponents(calendar: calendar, year: 2026, month: 10, day: d, hour: hour).date!
    }

    private func receipt(_ merchant: String, _ total: Decimal, on date: Date) -> Receipt {
        Receipt(merchant: merchant, date: date, total: total, category: .groceries)
    }

    func testSameStoreIsLooseAboutCasePunctuationAndBranchNames() {
        XCTAssertTrue(DuplicateFinder.sameStore("FRESHCO", "FreshCo"))
        XCTAssertTrue(DuplicateFinder.sameStore("Eggholic", "Eggholic- Indian Street Food (Brampton)"))
        XCTAssertTrue(DuplicateFinder.sameStore("FreshCo", "CHALO! FRESH CO"))
        XCTAssertFalse(DuplicateFinder.sameStore("Loblaws", "Farm Boy"))
        XCTAssertFalse(DuplicateFinder.sameStore("Bar", "Barbara's Bakery"))
        XCTAssertFalse(DuplicateFinder.sameStore("", ""))
    }

    func testAScanOfAReceiptYouHaveIsFound() {
        let saved = [receipt("FreshCo", 30.72, on: day(9)), receipt("FreshCo", 12.00, on: day(9))]
        var draft = ReceiptDraft()
        draft.merchant = "FRESHCO"
        draft.date = day(9, hour: 18)  // same day, different time
        draft.total = 30.72
        XCTAssertTrue(DuplicateFinder.find(draft, in: saved, calendar: calendar) === saved[0])
        draft.date = day(10)
        XCTAssertNil(DuplicateFinder.find(draft, in: saved, calendar: calendar))
    }

    func testGroupsCollectLookAlikesOnly() {
        let a = receipt("FreshCo", 30.72, on: day(9))
        let b = receipt("FRESHCO", 30.72, on: day(9))
        let c = receipt("Farm Boy", 30.72, on: day(9))  // same day and total, different store
        let d = receipt("FreshCo", 30.72, on: day(8))
        let groups = DuplicateFinder.groups(in: [a, b, c, d], calendar: calendar)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(ObjectIdentifier.init)), [ObjectIdentifier(a), ObjectIdentifier(b)])
    }
}
