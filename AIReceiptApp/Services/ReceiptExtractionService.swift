import Foundation

/// Chooses which `ReceiptExtractor` the app uses:
/// - the real backend (`LLMReceiptExtractor`) when `EXTRACTION_API_HOST` is set,
/// - otherwise `MockReceiptExtractor`, so the flow still runs end to end.
///
/// `current` is a `var` so tests or a debug menu can substitute an extractor.
enum ReceiptExtractionService {
    static var current: ReceiptExtractor = {
        if let baseURL = AppConfig.extractionAPIBaseURL {
            return LLMReceiptExtractor(baseURL: baseURL)
        }
        return MockReceiptExtractor()
    }()
}
