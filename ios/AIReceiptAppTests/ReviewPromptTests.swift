import XCTest

@testable import AIReceiptApp

final class ReviewPromptTests: XCTestCase {
    func testAsksOnlyAtMilestones() {
        let asked = (1...30).filter {
            ReviewPrompt.shouldAsk(savedCount: $0, lastAskedVersion: "", currentVersion: "1.0.2")
        }
        XCTAssertEqual(asked, [3, 10, 25])
    }

    func testAtMostOncePerVersion() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(savedCount: 10, lastAskedVersion: "1.0.2", currentVersion: "1.0.2"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(savedCount: 10, lastAskedVersion: "1.0.2", currentVersion: "1.1.0"))
    }
}
