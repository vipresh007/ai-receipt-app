import UIKit
import XCTest

@testable import AIReceiptApp

final class ImageScalingTests: XCTestCase {
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testLargePortraitPhotoIsCappedOnItsLongEdge() {
        let scaled = image(width: 3024, height: 4032).scaledDown(toLongEdge: 2048)
        XCTAssertEqual(scaled.size.height * scaled.scale, 2048)
        XCTAssertEqual(scaled.size.width * scaled.scale, 1536)
    }

    func testLandscapeKeepsItsAspectRatio() {
        let scaled = image(width: 4000, height: 1000).scaledDown(toLongEdge: 2048)
        XCTAssertEqual(scaled.size.width * scaled.scale, 2048)
        XCTAssertEqual(scaled.size.height * scaled.scale, 512)
    }

    func testSmallImageIsLeftAlone() {
        let original = image(width: 800, height: 1200)
        XCTAssertTrue(original.scaledDown(toLongEdge: 2048) === original)
    }
}
