import XCTest
@testable import Accountabilibrosis

final class SmokeTests: XCTestCase {
    func testTestsRunInsideTheAppBundle() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.accountabilibrosis.app")
    }

    func testAppleEventsUsageDescriptionIsPresent() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String
        XCTAssertEqual(text, "Accountabilibrosis opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in.")
    }
}
