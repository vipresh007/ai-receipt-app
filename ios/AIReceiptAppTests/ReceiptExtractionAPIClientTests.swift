import XCTest
@testable import AIReceiptApp

final class ReceiptExtractionAPIClientTests: XCTestCase {
    private func decode(_ json: String) throws -> ReceiptExtractionAPIClient.ResponseBody {
        try JSONDecoder().decode(
            ReceiptExtractionAPIClient.ResponseBody.self,
            from: Data(json.utf8)
        )
    }

    func testFullResponseMapsToDraft() throws {
        let body = try decode(#"""
        {
          "merchant": "Blue Bottle Coffee",
          "date": "2026-09-01",
          "total": "12.50",
          "tax": "1.03",
          "category": "restaurants",
          "items": [
            { "name": "Latte", "price": "5.25", "quantity": 2 },
            { "name": "Croissant", "price": "3.00" }
          ],
          "confidence": 0.94
        }
        """#)

        let draft = body.asDraft(imageData: nil)

        XCTAssertEqual(draft.merchant, "Blue Bottle Coffee")
        XCTAssertEqual(draft.total, Decimal(string: "12.50"))
        XCTAssertEqual(draft.tax, Decimal(string: "1.03"))
        XCTAssertEqual(draft.category, .restaurants)
        XCTAssertEqual(draft.items.count, 2)
        XCTAssertEqual(draft.items.first?.quantity, 2)
        XCTAssertEqual(draft.items.last?.quantity, 1) // defaulted
        XCTAssertTrue(draft.isValid)
    }

    func testMinimalResponseUsesSafeDefaults() throws {
        let body = try decode(#"""
        { "merchant": "", "total": "0" }
        """#)

        let draft = body.asDraft(imageData: nil)

        XCTAssertEqual(draft.merchant, "")
        XCTAssertEqual(draft.total, 0)
        XCTAssertEqual(draft.tax, 0)
        XCTAssertEqual(draft.category, .other)
        XCTAssertTrue(draft.items.isEmpty)
        XCTAssertFalse(draft.isValid) // empty merchant + zero total
    }

    func testUnknownCategoryFallsBackToOther() throws {
        let body = try decode(#"""
        { "merchant": "Corner Store", "total": "4.00", "category": "snacks" }
        """#)

        XCTAssertEqual(body.asDraft(imageData: nil).category, .other)
    }

    func testInvalidDateFallsBackToNow() throws {
        let body = try decode(#"""
        { "merchant": "X", "total": "1.00", "date": "not-a-date" }
        """#)

        let draft = body.asDraft(imageData: nil)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: draft.date),
            Calendar.current.startOfDay(for: .now)
        )
    }
}
