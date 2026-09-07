import Foundation

/// Single place to choose which `ReceiptExtractor` the app uses.
///
/// Today it points at the mock so the flow is clickable end-to-end. Switch to
/// `LLMReceiptExtractor()` once `callExtractionAPI(lines:)` is implemented.
enum ReceiptExtractionService {
    static var current: ReceiptExtractor = MockReceiptExtractor()
}
