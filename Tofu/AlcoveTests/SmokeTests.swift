import XCTest
@testable import Alcove

final class SmokeTests: XCTestCase {
    func testTestsRunInsideTheAppBundle() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.alcove.app")
    }

    func testAppleEventsUsageDescriptionIsPresent() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String
        XCTAssertEqual(text, "Alcove opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in.")
    }
}
