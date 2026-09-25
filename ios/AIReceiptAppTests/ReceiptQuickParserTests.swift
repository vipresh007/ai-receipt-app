import CoreGraphics
import XCTest

@testable import AIReceiptApp

final class ReceiptQuickParserTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private lazy var today = day(2026, 9, 25)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func parse(_ rows: [String]) -> ReceiptDraft {
        ReceiptQuickParser.draft(from: rows, today: today, calendar: calendar)
    }

    // MARK: - Whole receipt

    func testReadsTheNorthfieldReceipt() {
        let draft = parse([
            "NORTHFIELD MARKET",
            "214 King St W, Waterloo ON",
            "09/22/2026 17:42",
            "OAT MILK 1L  4.49",
            "SOURDOUGH LOAF  6.50",
            "COFFEE BEANS 340G  14.99",
            "SUBTOTAL  42.10",
            "HST 13%  0.65",
            "TOTAL  42.75",
            "VISA ****4417  42.75",
            "THANK YOU FOR SHOPPING",
        ])
        XCTAssertEqual(draft.merchant, "NORTHFIELD MARKET")
        XCTAssertEqual(draft.date, day(2026, 9, 22))
        XCTAssertEqual(draft.total, Decimal(string: "42.75"))
        XCTAssertEqual(draft.tax, Decimal(string: "0.65"))
        XCTAssertTrue(ReceiptQuickParser.isUseful(draft))
    }

    func testNothingRecognizableIsNotUseful() {
        let draft = parse(["blurry", "~~~"])
        XCTAssertEqual(draft.total, 0)
        XCTAssertFalse(ReceiptQuickParser.isUseful(draft))
    }

    // MARK: - Total

    func testTotalSkipsSubtotalAndSavings() {
        XCTAssertEqual(
            ReceiptQuickParser.total(in: ["SUBTOTAL 20.00", "TOTAL SAVINGS 3.00", "TOTAL 22.60"]),
            Decimal(string: "22.60")
        )
    }

    func testTotalLabelWithAmountOnTheNextRow() {
        XCTAssertEqual(ReceiptQuickParser.total(in: ["TOTAL", "$1,204.50"]), Decimal(string: "1204.50"))
    }

    func testAmountDueBeatsAPlainTotal() {
        XCTAssertEqual(
            ReceiptQuickParser.total(in: ["TOTAL ITEMS 3", "TOTAL 18.00", "AMOUNT DUE 16.00"]),
            Decimal(string: "16.00")
        )
    }

    func testNoTotalLabelLeavesTotalEmpty() {
        XCTAssertNil(ReceiptQuickParser.total(in: ["COFFEE 4.50", "CASH 10.00", "CHANGE 5.50"]))
    }

    // MARK: - Tax

    func testTaxSumsSeparateLines() {
        XCTAssertEqual(ReceiptQuickParser.tax(in: ["GST 5%  1.00", "PST 7%  1.40"]), Decimal(string: "2.40"))
    }

    func testTotalTaxRowWins() {
        XCTAssertEqual(
            ReceiptQuickParser.tax(in: ["GST 1.00", "PST 1.40", "TOTAL TAX 2.40"]),
            Decimal(string: "2.40")
        )
    }

    func testTaxableAmountIsNotTax() {
        XCTAssertNil(ReceiptQuickParser.tax(in: ["TAXABLE AMOUNT 20.00"]))
    }

    // MARK: - Date

    func testDateFormats() {
        let cases: [(String, Date)] = [
            ("2026-09-22", day(2026, 9, 22)),
            ("DATE: 09/22/26", day(2026, 9, 22)),
            ("22/09/2026", day(2026, 9, 22)),  // only day-first is a real date
            ("03/04/2026", day(2026, 3, 4)),  // ambiguous → month-first
            ("Sep 22, 2026 5:42 PM", day(2026, 9, 22)),
            ("22 SEPT 2026", day(2026, 9, 22)),
        ]
        for (row, expected) in cases {
            XCTAssertEqual(ReceiptQuickParser.date(in: [row], today: today, calendar: calendar), expected, row)
        }
    }

    func testImplausibleDatesAreIgnored() {
        XCTAssertNil(ReceiptQuickParser.date(in: ["12/31/2026"], today: today, calendar: calendar))  // future
        XCTAssertNil(ReceiptQuickParser.date(in: ["02/30/2026"], today: today, calendar: calendar))  // no such day
        XCTAssertNil(ReceiptQuickParser.date(in: ["01/15/2019"], today: today, calendar: calendar))  // too old
    }

    // MARK: - Merchant

    func testMerchantSkipsGreetingsAndAddresses() {
        XCTAssertEqual(
            ReceiptQuickParser.merchant(in: ["WELCOME TO", "123 Main St", "Bluebird Cafe", "Tel 555"]),
            "Bluebird Cafe"
        )
    }

    // MARK: - OCR rows

    func testBlocksOnOneLineJoinLeftToRight() {
        typealias Piece = ReceiptTextRecognizer.Piece
        let rows = ReceiptTextRecognizer.rows(from: [
            Piece(text: "42.75", box: CGRect(x: 0.8, y: 0.40, width: 0.1, height: 0.02)),
            Piece(text: "NORTHFIELD MARKET", box: CGRect(x: 0.3, y: 0.90, width: 0.4, height: 0.03)),
            Piece(text: "TOTAL", box: CGRect(x: 0.1, y: 0.405, width: 0.1, height: 0.02)),
        ])
        XCTAssertEqual(rows, ["NORTHFIELD MARKET", "TOTAL  42.75"])
    }

    func testTiltedPhotoPairsLabelsWithTheirOwnPrices() {
        // Tilted ~2°: each price (right) sits higher than its label (left),
        // level with the label above. Straight-across grouping would pair
        // "SUBTOTAL" with the tax and "HST" with the total.
        typealias Piece = ReceiptTextRecognizer.Piece
        let slope: CGFloat = 0.035
        func piece(_ text: String, x: CGFloat, y: CGFloat) -> Piece {
            Piece(text: text, box: CGRect(x: x, y: y + slope * x, width: 0.15, height: 0.02), slope: slope)
        }
        let rows = ReceiptTextRecognizer.rows(from: [
            piece("SUBTOTAL", x: 0.1, y: 0.50), piece("42.10", x: 0.8, y: 0.50),
            piece("HST 13%", x: 0.1, y: 0.475), piece("0.65", x: 0.8, y: 0.475),
            piece("TOTAL", x: 0.1, y: 0.45), piece("42.75", x: 0.8, y: 0.45),
        ])
        XCTAssertEqual(rows, ["SUBTOTAL  42.10", "HST 13%  0.65", "TOTAL  42.75"])
    }

    // MARK: - Merging the server's read

    func testServerFillsUntouchedFieldsAndKeepsEdits() {
        let baseline = parse(["SHOP", "TOTAL 10.00"])
        var onScreen = baseline
        onScreen.total = 12  // the user corrected the total

        var server = ReceiptDraft()
        server.merchant = "Shop & Co"
        server.total = 10
        server.category = .groceries
        server.items = [ReceiptLineItem(name: "Milk", price: 10)]

        let merged = onScreen.refined(with: server, baseline: baseline)
        XCTAssertEqual(merged.merchant, "Shop & Co")
        XCTAssertEqual(merged.total, 12)
        XCTAssertEqual(merged.category, .groceries)
        XCTAssertEqual(merged.items.map(\.name), ["Milk"])
    }

    func testEmptyServerFieldsDontWipeTheQuickRead() {
        let baseline = parse(["SHOP", "TOTAL 10.00"])
        let merged = baseline.refined(with: ReceiptDraft(), baseline: baseline)
        XCTAssertEqual(merged.merchant, "SHOP")
        XCTAssertEqual(merged.total, 10)
    }
}
