import UIKit

/// Production extractor: OCR the receipt on-device, then send the text to an LLM
/// that returns structured JSON. Fill in `callExtractionAPI(lines:)` with the
/// real backend request and switch `ReceiptExtractionService.current` to this.
struct LLMReceiptExtractor: ReceiptExtractor {
    var recognizer = ReceiptTextRecognizer()

    func extractReceipt(from image: UIImage) async throws -> ReceiptDraft {
        let lines = try await recognizer.recognizeText(in: image)
        var draft = try await callExtractionAPI(lines: lines)
        draft.imageData = image.jpegData(compressionQuality: 0.7)
        return draft
    }

    private func callExtractionAPI(lines: [String]) async throws -> ReceiptDraft {
        // TODO: POST `lines` (or the image) to the extraction endpoint and
        // decode the response into a ReceiptDraft. The endpoint should return:
        // merchant, date, total, tax, category, and optional line items.
        //
        // Keep the endpoint URL + any keys in Secrets.xcconfig (git-ignored),
        // never in source.
        _ = lines
        throw ReceiptExtractionError.notConfigured
    }
}
