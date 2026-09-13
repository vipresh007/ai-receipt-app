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

    func testScansRemainingDecodesFromSnakeCase() throws {
        let withCount = try decode(#"{ "merchant": "X", "total": "1.00", "scans_remaining": 14 }"#)
        XCTAssertEqual(withCount.scansRemaining, 14)

        let withoutCount = try decode(#"{ "merchant": "X", "total": "1.00" }"#)
        XCTAssertNil(withoutCount.scansRemaining)
    }

    func testErrorMessagePrefersDetailThenError() {
        XCTAssertEqual(
            ReceiptExtractionAPIClient.errorMessage(from: Data(#"{"detail":"nope"}"#.utf8)),
            "nope"
        )
        XCTAssertEqual(
            ReceiptExtractionAPIClient.errorMessage(from: Data(#"{"error":"legacy"}"#.utf8)),
            "legacy"
        )
        XCTAssertNil(ReceiptExtractionAPIClient.errorMessage(from: Data("not json".utf8)))
    }

    func testReceiptWriteEncodesBackendKeys() throws {
        let item = ReceiptExtractionAPIClient.ReceiptWrite(
            merchant: "Corner Store",
            date: "2026-09-03",
            total: "9.99",
            tax: "0.80",
            category: "groceries",
            currency: "USD",
            items: [.init(name: "Milk", price: "3.50", quantity: 1)],
            imageBase64: nil
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        XCTAssertEqual(json?["merchant"] as? String, "Corner Store")
        XCTAssertEqual(json?["date"] as? String, "2026-09-03")
        XCTAssertNil(json?["imageBase64"])  // nil optional is omitted
        XCTAssertEqual((json?["items"] as? [[String: Any]])?.first?["price"] as? String, "3.50")
    }

    func testResponseCarriesServerIdWhenSignedIn() throws {
        let signedIn = try decode(#"{ "id": "abc-123", "merchant": "X", "total": "1.00" }"#)
        XCTAssertEqual(signedIn.id, "abc-123")
        let anon = try decode(#"{ "merchant": "X", "total": "1.00" }"#)
        XCTAssertNil(anon.id)
    }

    func testAuthorizedBuildsRealQueryStringNotEncodedPath() throws {
        // Regression: `appendingPathComponent` used to swallow the whole
        // "v1/receipts?limit=200" string as a literal path segment, so the
        // "?" and "=" got percent-encoded and the server 404'd on a path
        // that literally contained "%3Flimit%3D200".
        let client = ReceiptExtractionAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            authToken: "token"
        )
        let request = try client.authorized("v1/receipts?limit=200", method: "GET")
        XCTAssertEqual(request.url?.path, "/v1/receipts")
        XCTAssertEqual(request.url?.query, "limit=200")
        XCTAssertFalse(request.url?.absoluteString.contains("%3F") ?? true)
    }

    func testAuthorizedHandlesPathWithoutQuery() throws {
        let client = ReceiptExtractionAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            authToken: "token"
        )
        let request = try client.authorized("v1/auth/me", method: "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/auth/me")
        XCTAssertNil(request.url?.query)
    }

    func testReceiptDTODecodesSnakeCaseAndMakesReceipt() throws {
        let dto = try JSONDecoder().decode(
            ReceiptExtractionAPIClient.ReceiptDTO.self,
            from: Data(
                #"""
                {
                  "id": "r-1",
                  "merchant": "Blue Bottle",
                  "purchased_at": "2026-09-01",
                  "total": "12.50",
                  "tax": "1.03",
                  "currency": "USD",
                  "category_slug": "restaurants",
                  "image_blob_url": null,
                  "extraction_confidence": 0.9,
                  "line_items": [{ "name": "Latte", "price": "5.25", "quantity": 2 }]
                }
                """#.utf8
            )
        )
        XCTAssertEqual(dto.categorySlug, "restaurants")

        let receipt = dto.makeReceipt()
        XCTAssertEqual(receipt.remoteID, "r-1")
        XCTAssertEqual(receipt.merchant, "Blue Bottle")
        XCTAssertEqual(receipt.total, Decimal(string: "12.50"))
        XCTAssertEqual(receipt.category, .restaurants)
        XCTAssertEqual(receipt.items.first?.quantity, 2)
    }
}
