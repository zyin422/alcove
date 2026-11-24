import XCTest
@testable import Tofu

final class SpiritLinesTests: XCTestCase {
    func testClosedLinesRotateByHostAndStayInThePool() {
        let line = SpiritLines.closedTab("reddit.com")
        XCTAssertEqual(line, SpiritLines.closedTab("reddit.com"))
        XCTAssertTrue(line.contains("reddit.com"))
        XCTAssertNotEqual(SpiritLines.slot("a", count: 3), SpiritLines.slot("zzzz", count: 3))
        XCTAssertLessThan(SpiritLines.slot("reddit.com", count: 3), 3)
    }

    func testAppHiddenLinesIncludeAppName() {
        let line = SpiritLines.appHidden("Discord")
        XCTAssertTrue(line.contains("Discord"))
        XCTAssertEqual(line, SpiritLines.appHidden("Discord"))
    }

    func testQuestionTrimsWhitespaceAndFormatsCorrectly() {
        XCTAssertEqual(SpiritLines.question(host: "docs.swift.org", title: "   "), "Does docs.swift.org help with this?")
        XCTAssertEqual(SpiritLines.question(host: "github.com", title: "Pull Request 42"), "Does github.com help? Pull Request 42")
    }

    func testSpiritNoticeEquality() {
        XCTAssertEqual(SpiritNotice.tabClosed("youtube.com"), SpiritNotice.tabClosed("youtube.com"))
        XCTAssertNotEqual(SpiritNotice.tabClosed("youtube.com"), SpiritNotice.appHidden("YouTube"))
    }
}
