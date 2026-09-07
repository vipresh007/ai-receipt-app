import UIKit

/// Turns a receipt image into a structured `ReceiptDraft`.
///
/// The app ships with `MockReceiptExtractor` so the full capture → confirm →
/// save flow works without a backend. Swap in `LLMReceiptExtractor` once the
/// extraction API is wired up (see `ReceiptExtractionService`).
protocol ReceiptExtractor {
    func extractReceipt(from image: UIImage) async throws -> ReceiptDraft
}

enum ReceiptExtractionError: LocalizedError {
    case couldNotReadImage
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .couldNotReadImage:
            "We couldn't read that image. Try a clearer, well-lit photo."
        case .notConfigured:
            "Receipt extraction isn't configured yet."
        case .server(let message):
            message
        }
    }
}
