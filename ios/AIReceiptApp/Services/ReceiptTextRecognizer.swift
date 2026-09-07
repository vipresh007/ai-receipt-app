import UIKit
import Vision

/// On-device OCR using the Vision framework. The recognized lines are the raw
/// input an LLM-based extractor parses into structured fields.
struct ReceiptTextRecognizer {
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw ReceiptExtractionError.couldNotReadImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
