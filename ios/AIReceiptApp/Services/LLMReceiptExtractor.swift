import UIKit

/// Production extractor: OCR the receipt on-device for extra context, then hand
/// the image + text to our backend (`ReceiptExtractionAPIClient`), which runs
/// the LLM. Selected by `ReceiptExtractionService` when `EXTRACTION_API_HOST`
/// is configured.
struct LLMReceiptExtractor: ReceiptExtractor {
    var baseURL: URL
    /// Bearer token when signed in; `nil` for anonymous callers.
    var authToken: String?
    /// Anonymous device identifier, sent when `authToken` is nil.
    var deviceID: String?
    var recognizer = ReceiptTextRecognizer()

    /// Longest side, in pixels, of the image we upload (and keep locally).
    static let maxUploadEdge: CGFloat = 2048

    func extractReceipt(from image: UIImage) async throws -> ReceiptExtractionResult {
        // A full-resolution camera photo is several MB — seconds of upload on
        // cellular — and the model downsamples past ~2048px anyway.
        let image = image.scaledDown(toLongEdge: Self.maxUploadEdge)
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw ReceiptExtractionError.couldNotReadImage
        }

        // OCR is best-effort context for the backend — failure here is non-fatal.
        let ocrLines = (try? await recognizer.recognizeText(in: image)) ?? []

        let client = ReceiptExtractionAPIClient(
            baseURL: baseURL,
            authToken: authToken,
            deviceID: deviceID
        )
        return try await client.extract(imageData: imageData, ocrLines: ocrLines)
    }
}

extension UIImage {
    /// This image redrawn so its longer side is at most `maxEdge` pixels
    /// (aspect ratio kept, orientation baked in). Returns `self` if it's
    /// already small enough.
    func scaledDown(toLongEdge maxEdge: CGFloat) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxEdge else { return self }
        let ratio = maxEdge / longEdge
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
