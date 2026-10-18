import XCTest
@testable import Tofu

final class SpiritLayoutTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testEaseStartsSlowAndIsFastestThroughTheMiddle() {
        XCTAssertEqual(SpiritLayout.ease(0), 0, accuracy: 0.001)
        XCTAssertEqual(SpiritLayout.ease(1), 1, accuracy: 0.001)
        XCTAssertLessThan(SpiritLayout.ease(0.25), 0.25)
        let early = SpiritLayout.ease(0.2) - SpiritLayout.ease(0)
        let middle = SpiritLayout.ease(0.6) - SpiritLayout.ease(0.4)
        XCTAssertGreaterThan(middle, early)
    }

    func testPatrolCoversMoreGroundThroughTheMiddleOfALap() {
        let left = SpiritLayout.patrolFrame(at: 0, visible: visible).midX
        let quarter = SpiritLayout.patrolPeriod * 0.1
        let early = SpiritLayout.patrolFrame(at: quarter, visible: visible).midX - left
        let midStart = SpiritLayout.patrolFrame(at: SpiritLayout.patrolPeriod * 0.15, visible: visible).midX
        let midEnd = SpiritLayout.patrolFrame(at: SpiritLayout.patrolPeriod * 0.25, visible: visible).midX
        XCTAssertGreaterThan(midEnd - midStart, early)
        XCTAssertLessThan(SpiritLayout.patrolFrame(at: 0, visible: visible).width, MiniTimerLayout.panelSize.width)
    }

    func testVisitLandsOnTheTopEdgeOfTheBrowserWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quartz = CGRect(x: 100, y: 40, width: 800, height: 500)
        let frame = SpiritLayout.visitFrame(quartzWindow: quartz, primaryHeight: 900, visible: screen)
        XCTAssertEqual(frame.size, SpiritLayout.restSize)
        XCTAssertEqual(frame.midX, 500, accuracy: 0.1)
        XCTAssertEqual(frame.midY, 900 - 40 - SpiritLayout.restSize.height * 0.45 + SpiritLayout.restSize.height / 2,
                       accuracy: 0.1)
    }

    func testExpandedCardGrowsDownFromTheCircle() {
        let small = CGRect(x: 400, y: 800, width: 52, height: 52)
        let card = SpiritLayout.expandedFrame(around: small, visible: visible)
        XCTAssertEqual(card.size, SpiritLayout.expandedSize)
        XCTAssertEqual(card.maxY, small.maxY)
        XCTAssertEqual(card.midX, small.midX)
        XCTAssertGreaterThan(card.width, small.width)
    }

    func testFramesStayInsideTheVisibleScreen() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 300)
        let card = SpiritLayout.expandedFrame(around: CGRect(x: -80, y: 400, width: 52, height: 52), visible: screen)
        XCTAssertTrue(screen.contains(card))
        XCTAssertEqual(card.minX, 0)
        XCTAssertEqual(card.maxY, screen.maxY)
    }

    func testClosedLinesRotateByHostAndStayInThePool() {
        let line = SpiritLines.closedTab("reddit.com")
        XCTAssertEqual(line, SpiritLines.closedTab("reddit.com"))
        XCTAssertTrue(line.contains("reddit.com"))
        XCTAssertNotEqual(SpiritLines.slot("a", count: 3), SpiritLines.slot("zzzz", count: 3))
        XCTAssertLessThan(SpiritLines.slot("reddit.com", count: 3), 3)
    }

    func testQuestionAndHiddenAppNameTheThing() {
        XCTAssertEqual(SpiritLines.question(host: "reddit.com", title: ""), "Does reddit.com help with this?")
        XCTAssertEqual(SpiritLines.question(host: "reddit.com", title: "Lecture 3"),
                       "Does reddit.com help? Lecture 3")
        XCTAssertTrue(SpiritLines.appHidden("Discord").contains("Discord"))
    }
}
