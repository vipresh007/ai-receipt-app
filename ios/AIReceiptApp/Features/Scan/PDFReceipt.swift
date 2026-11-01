import PDFKit
import UIKit

/// A PDF receipt or invoice as one image (its first pages, stacked), so it
/// goes through the same read as a photo.
enum PDFReceipt {
    static let maxPages = 2

    static func image(from url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url) else { return nil }
        return image(from: document)
    }

    static func image(from data: Data) -> UIImage? {
        guard let document = PDFDocument(data: data) else { return nil }
        return image(from: document)
    }

    private static func image(from document: PDFDocument) -> UIImage? {
        let pages = (0..<min(document.pageCount, maxPages)).compactMap(document.page(at:))
        guard !pages.isEmpty else { return nil }
        let width: CGFloat = 1240
        let sizes = pages.map { page -> CGSize in
            let box = page.bounds(for: .mediaBox)
            return CGSize(width: width, height: box.height * width / max(box.width, 1))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: sizes.reduce(0) { $0 + $1.height }), format: format
        )
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(context.format.bounds)
            var y: CGFloat = 0
            for (page, size) in zip(pages, sizes) {
                let box = page.bounds(for: .mediaBox)
                let cg = context.cgContext
                cg.saveGState()
                // PDF space is bottom-up; flip into this page's slot.
                cg.translateBy(x: 0, y: y + size.height)
                cg.scaleBy(x: size.width / box.width, y: -size.height / box.height)
                cg.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                y += size.height
            }
        }
    }
}
