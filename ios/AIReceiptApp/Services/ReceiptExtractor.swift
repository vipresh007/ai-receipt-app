import UIKit

/// Turns a receipt image into a structured `ReceiptDraft`.
///
/// The app ships with `MockReceiptExtractor` so the full capture → confirm →
/// save flow works without a backend. Swap in `LLMReceiptExtractor` once the
/// extraction API is wired up (see `ReceiptExtractionService`).
protocol ReceiptExtractor {
    /// `ocrLines`: on-device OCR rows for this image (`ReceiptTextRecognizer`),
    /// already computed by the scan flow and passed along as context.
    func extractReceipt(from image: UIImage, ocrLines: [String]) async throws -> ReceiptExtractionResult
}

enum ReceiptExtractionError: LocalizedError, Equatable {
    case couldNotReadImage
    case notConfigured
    /// Anonymous device has used all its free scans (HTTP 402). Sign in to continue.
    case quotaExhausted(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .couldNotReadImage:
            "We couldn't read that image. Try a clearer, well-lit photo."
        case .notConfigured:
            "Receipt extraction isn't configured yet."
        case .quotaExhausted(let message):
            message
        case .server(let message):
            message
        }
    }
}

/// One extraction outcome: the editable draft, how many free scans remain on
/// this device (anonymous only; `nil` when signed in), and the server receipt
/// id (signed-in only; the backend already persisted it).
struct ReceiptExtractionResult {
    var draft: ReceiptDraft
    var scansRemaining: Int?
    var serverID: String?
}
