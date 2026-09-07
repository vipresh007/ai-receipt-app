import UIKit

/// Production extractor: OCR the receipt on-device for extra context, then hand
/// the image + text to our backend (`ReceiptExtractionAPIClient`), which runs
/// the LLM. Selected automatically by `ReceiptExtractionService` when
/// `EXTRACTION_API_HOST` is configured.
struct LLMReceiptExtractor: ReceiptExtractor {
    var baseURL: URL
    /// Provided by the sign-in flow once it exists; sent as a bearer token.
    var authToken: String?
    var recognizer = ReceiptTextRecognizer()

    func extractReceipt(from image: UIImage) async throws -> ReceiptDraft {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw ReceiptExtractionError.couldNotReadImage
        }

        // OCR is best-effort context for the backend — failure here is non-fatal.
        let ocrLines = (try? await recognizer.recognizeText(in: image)) ?? []

        let client = ReceiptExtractionAPIClient(baseURL: baseURL, authToken: authToken)
        return try await client.extract(imageData: imageData, ocrLines: ocrLines)
    }
}
