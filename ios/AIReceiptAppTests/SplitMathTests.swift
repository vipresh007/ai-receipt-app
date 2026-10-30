import XCTest
@testable import AIReceiptApp

/// The live preview must match the server (backend/tests/test_split_math.py),
/// so these mirror its cases.
final class SplitMathTests: XCTestCase {
    private func shares(
        _ total: Decimal,
        _ mode: SplitMath.Mode,
        _ inputs: [SplitMath.Input],
        _ items: [Decimal] = []
    ) -> [Decimal]? {
        try? SplitMath.shares(total: total, mode: mode, inputs: inputs, itemPrices: items).get()
    }

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    func testEvenSplitHandsOutLeftoverCentsAndAddsUp() {
        let result = shares(100, .even, Array(repeating: .init(), count: 3))
        XCTAssertEqual(result, [d("33.34"), d("33.33"), d("33.33")])
    }

    func testItemsSplitSharesTaxInProportion() {
        // Pasta 20 (A), salad 10 (B), bread 6 (both); 39.60 incl. 3.60 tax.
        let result = shares(
            d("39.60"), .items,
            [.init(itemIndexes: [0, 2]), .init(itemIndexes: [1, 2])],
            [20, 10, 6]
        )
        XCTAssertEqual(result, [d("25.30"), d("14.30")])
    }

    func testUnassignedItemsAreSharedByEveryone() {
        let result = shares(16, .items, [.init(itemIndexes: [0]), .init()], [10, 6])
        XCTAssertEqual(result, [13, 3])
    }

    func testDiscountReducesSharesProportionally() {
        let result = shares(36, .items, [.init(itemIndexes: [0]), .init(itemIndexes: [1])], [30, 10])
        XCTAssertEqual(result, [27, 9])
    }

    func testThreeWayItemsWithSharedStarterAddUpExactly() {
        // Same dinner the API produced 29.68 / 30.89 / 32.09 for.
        let result = shares(
            d("92.66"), .items,
            [.init(itemIndexes: [0, 4]), .init(itemIndexes: [1, 3, 4]), .init(itemIndexes: [2, 3, 4])],
            [21, 19, 20, 6, 11]
        )
        XCTAssertEqual(result, [d("29.68"), d("30.89"), d("32.09")])
    }

    func testSharesDivideTheTotalByParts() {
        // Same as the server: 2 and 3 parts of 30.72.
        XCTAssertEqual(shares(d("30.72"), .shares, [.init(weight: 2), .init(weight: 3)]), [d("12.29"), d("18.43")])
        XCTAssertEqual(shares(9, .shares, [.init(), .init(weight: 2)]), [3, 6])  // blank = 1
        XCTAssertEqual(
            SplitMath.shares(total: 9, mode: .shares, inputs: [.init(weight: 0)], itemPrices: []), .failure(.noShares)
        )
    }

    func testPercentagesMustMake100() {
        XCTAssertEqual(shares(50, .percent, [.init(weight: 40), .init(weight: 60)]), [20, 30])
        XCTAssertEqual(
            SplitMath.shares(total: 10, mode: .percent, inputs: [.init(weight: 40), .init(weight: 50)], itemPrices: []),
            .failure(.percentNot100(90))
        )
    }

    func testCustomAmountsMustAddUp() {
        let bad = SplitMath.shares(
            total: 50, mode: .custom, inputs: [.init(amount: 20), .init(amount: 20)], itemPrices: []
        )
        XCTAssertEqual(bad, .failure(.amountsDontAddUp(total: 50, entered: 40)))
        XCTAssertEqual(shares(50, .custom, [.init(amount: 30), .init(amount: 20)]), [30, 20])
    }

    func testMissingCustomAmountIsReported() {
        let result = SplitMath.shares(total: 10, mode: .custom, inputs: [.init(amount: 10), .init()], itemPrices: [])
        XCTAssertEqual(result, .failure(.missingAmount))
    }

    func testSplitReceiptCountsOnlyMyShareInSpending() {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 6, day: 15).date!
        let split = Receipt(merchant: "Pizzeria", date: now, total: 60, category: .restaurants)
        split.myShare = 20
        let mine = Receipt(merchant: "Grocer", date: now, total: 15, category: .groceries)

        let summary = SpendingSummary(receipts: [split, mine], calendar: calendar, now: now)
        XCTAssertEqual(summary.currentMonthTotal, 35)
    }

    func testSplitDecodesFromServerJSON() throws {
        let json = """
            {"id": "s1", "receipt_id": "r1", "group_id": null, "description": "Pizzeria",
             "total": "60.00", "currency": "CAD", "date": "2026-06-15", "mode": "items",
             "items": [{"name": "Pizza", "price": "60.00", "quantity": 1}],
             "participants": [{"id": "p1", "display_name": "Jordan", "member_id": null, "is_me": true,
               "is_payer": true, "item_indexes": [0], "amount": null, "share": "30.00", "paid": "60.00", "settled": false,
               "share_url": "https://tally.dataeaver.ca/s/abc"}],
             "my_share": "30.00", "is_owner": true, "can_edit": true, "repeat": "", "next_at": null}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let split = try decoder.decode(ReceiptExtractionAPIClient.SplitDTO.self, from: Data(json.utf8))
        XCTAssertEqual(split.mode, .items)
        XCTAssertEqual(split.myShareValue, 30)
        XCTAssertEqual(split.participants.first?.shareUrl, "https://tally.dataeaver.ca/s/abc")
        XCTAssertEqual(split.payer?.displayName, "Jordan")
    }

    func testPersonDecodesFromServerJSON() throws {
        let json = """
            {"id": "p1", "name": "Sam", "email": null, "has_account": false,
             "invite_url": "https://tally.dataeaver.ca/p/xyz", "invited_at": null,
             "balance": "-12.50", "outside_groups": "-12.50", "group_balances": [],
             "currency": "CAD", "can_email": false, "pay_to": {"paypal_me": "sam", "interac": null},
             "splits": [], "payments": [{"id": "pay1", "you_paid": true, "amount": "5.00",
               "note": "", "date": "2026-10-29", "can_delete": true}]}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let person = try decoder.decode(ReceiptExtractionAPIClient.PersonDetailDTO.self, from: Data(json.utf8))
        XCTAssertEqual(person.balanceValue, Decimal(string: "-12.50"))
        XCTAssertEqual(person.inviteUrl, "https://tally.dataeaver.ca/p/xyz")
        XCTAssertEqual(person.payments.first?.youPaid, true)
        XCTAssertEqual(person.payTo?.paypalMe, "sam")
        XCTAssertEqual(
            ISO8601DateFormatter.tally("2026-10-30T12:00:00.123456+00:00") != nil
                && ISO8601DateFormatter.tally("2026-10-30T12:00:00+00:00") != nil,
            true
        )
        XCTAssertEqual(PersonBalanceBadge.text(person.balanceValue, currency: "CAD", name: "Sam").hasPrefix("You owe"), true)
    }
}
