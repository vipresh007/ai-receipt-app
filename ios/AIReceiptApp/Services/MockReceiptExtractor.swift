import UIKit

/// Returns believable sample data after a short delay. Used for development and
/// previews until the real extraction service is available.
struct MockReceiptExtractor: ReceiptExtractor {
    func extractReceipt(from image: UIImage) async throws -> ReceiptExtractionResult {
        try await Task.sleep(for: .seconds(1.2))

        var draft = ReceiptDraft()
        draft.merchant = "Whole Foods Market"
        draft.date = .now
        draft.category = .groceries
        draft.items = [
            ReceiptLineItem(name: "Bananas", price: 1.79),
            ReceiptLineItem(name: "Oat milk", price: 4.29),
            ReceiptLineItem(name: "Chicken breast", price: 9.87),
            ReceiptLineItem(name: "Sourdough loaf", price: 5.50),
        ]
        let subtotal = draft.items.reduce(Decimal(0)) { $0 + $1.price }
        draft.tax = 1.34
        draft.total = subtotal + draft.tax
        draft.imageData = image.jpegData(compressionQuality: 0.7)
        return ReceiptExtractionResult(draft: draft, scansRemaining: nil, serverID: nil)
    }
}
