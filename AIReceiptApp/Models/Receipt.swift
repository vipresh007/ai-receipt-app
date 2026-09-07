import Foundation
import SwiftData

/// A saved expense, created from a scanned receipt.
@Model
final class Receipt {
    var merchant: String
    var date: Date
    var total: Decimal
    var tax: Decimal
    var note: String
    var createdAt: Date

    /// Persisted separately from the row; may be large.
    @Attribute(.externalStorage) var imageData: Data?

    /// Stored as a raw string for schema stability; use `category` in code.
    private var categoryRaw: String

    /// Line items are a value type stored inline — good enough for the MVP.
    var items: [ReceiptLineItem]

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        merchant: String,
        date: Date,
        total: Decimal,
        tax: Decimal = 0,
        category: ExpenseCategory = .other,
        items: [ReceiptLineItem] = [],
        note: String = "",
        imageData: Data? = nil
    ) {
        self.merchant = merchant
        self.date = date
        self.total = total
        self.tax = tax
        self.categoryRaw = category.rawValue
        self.items = items
        self.note = note
        self.createdAt = .now
        self.imageData = imageData
    }
}

/// One line on a receipt. Kept as a plain `Codable` struct so SwiftData stores
/// it inline on `Receipt` without a separate model/relationship.
struct ReceiptLineItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var price: Decimal
    var quantity: Int

    init(id: UUID = UUID(), name: String, price: Decimal, quantity: Int = 1) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}
