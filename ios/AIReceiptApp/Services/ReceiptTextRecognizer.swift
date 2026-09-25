import UIKit
import Vision

/// On-device OCR using the Vision framework. The rows feed the quick on-device
/// read (`ReceiptQuickParser`) and go to the backend as context for the LLM.
struct ReceiptTextRecognizer {
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw ReceiptExtractionError.couldNotReadImage
        }

        let pieces: [Piece] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let pieces = observations.compactMap { observation -> Piece? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    // The text line's own tilt, from its corners (too short a line gives noise).
                    let run = observation.bottomRight.x - observation.bottomLeft.x
                    let slope = run > 0.04 ? (observation.bottomRight.y - observation.bottomLeft.y) / run : nil
                    return Piece(text: text, box: observation.boundingBox, slope: slope)
                }
                continuation.resume(returning: pieces)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation)
            )
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return Self.rows(from: pieces)
    }

    struct Piece {
        var text: String
        /// Vision's normalized box: origin bottom-left, so a larger `midY` is higher up.
        var box: CGRect
        /// Rise over run of the text's baseline, when the line is long enough to tell.
        var slope: CGFloat?
    }

    /// Text rows, top to bottom. Vision returns text that's far apart on one
    /// printed line as separate blocks ("TOTAL" … "42.75"), so blocks that sit
    /// on the same line are joined left to right into one row. Photos are
    /// never quite level — a few degrees puts a right-hand price level with
    /// the label *above* its own — so "the same line" is measured along the
    /// page's median tilt, not straight across.
    static func rows(from pieces: [Piece]) -> [String] {
        let slopes = pieces.compactMap(\.slope).sorted()
        let tilt = slopes.isEmpty ? 0 : slopes[slopes.count / 2]
        func level(_ piece: Piece) -> CGFloat { piece.box.midY - tilt * piece.box.midX }

        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { level($0) > level($1) }) {
            if let first = rows.last?.first,
                abs(level(first) - level(piece)) < min(first.box.height, piece.box.height) * 0.5
            {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
