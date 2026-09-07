import Foundation

/// Editable, in-flight representation of a scanned receipt, shown on the
/// confirmation screen before it is persisted as a `Receipt`.
struct ReceiptDraft {
    var merchant: String = ""
    var date: Date = .now
    var total: Decimal = 0
    var tax: Decimal = 0
    var category: ExpenseCategory = .other
    var items: [ReceiptLineItem] = []
    var imageData: Data?

    var isValid: Bool {
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && total > 0
    }

    func makeReceipt() -> Receipt {
        Receipt(
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            total: total,
            tax: tax,
            category: category,
            items: items,
            imageData: imageData
        )
    }
}
