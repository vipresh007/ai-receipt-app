import SwiftUI
import XCTest

@testable import AIReceiptApp

final class LineItemTotalTests: XCTestCase {
    /// Bindings over plain local storage, like a Form row would get.
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
        var binding: Binding<T> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    func testEditingAPriceMovesTheTotalByTheDifference() {
        // Items 4.49 + 6.50; total 11.64 includes 0.65 of tax.
        let item = Box(ReceiptLineItem(name: "Oat milk", price: Decimal(string: "4.49")!))
        let total = Box(Decimal(string: "11.64")!)

        item.binding.priceMovingTotal(total.binding).wrappedValue = Decimal(string: "5.49")!

        XCTAssertEqual(item.value.price, Decimal(string: "5.49"))
        XCTAssertEqual(total.value, Decimal(string: "12.64"))  // tax still in it
    }

    func testTotalNeverGoesNegative() {
        let item = Box(ReceiptLineItem(name: "Refund", price: 10))
        let total = Box(Decimal(3))
        item.binding.priceMovingTotal(total.binding).wrappedValue = 0
        XCTAssertEqual(total.value, 0)
    }

    func testPriceSumOfDeletedItems() {
        let items = [
            ReceiptLineItem(name: "A", price: Decimal(string: "1.25")!),
            ReceiptLineItem(name: "B", price: Decimal(string: "2.50")!),
            ReceiptLineItem(name: "C", price: Decimal(string: "4.00")!),
        ]
        XCTAssertEqual(items.priceSum(at: IndexSet([0, 2])), Decimal(string: "5.25"))
    }
}
