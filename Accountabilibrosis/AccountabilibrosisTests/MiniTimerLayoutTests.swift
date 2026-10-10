import XCTest
@testable import Accountabilibrosis

final class MiniTimerLayoutTests: XCTestCase {
    private let size = CGSize(width: 240, height: 64)

    func testPanelSizeAndMarginMatchTheSpec() {
        XCTAssertEqual(MiniTimerLayout.panelSize, CGSize(width: 240, height: 64))
        XCTAssertEqual(MiniTimerLayout.topMargin, 8)
    }

    func testFrameIsCenteredHorizontallyEightPointsBelowTheTop() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 600, y: 803, width: 240, height: 64))
    }

    func testFrameFollowsTheVisibleFrameOrigin() {
        // Dock on the left and a bottom inset: the panel is centered within the visible frame, not the screen.
        let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 580, y: 778, width: 240, height: 64))
    }

    func testCustomTopMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible, topMargin: 20),
                       CGRect(x: 600, y: 791, width: 240, height: 64))
    }

    func testOddWidthRoundsXDownToAWholePoint() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 700)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 380, y: 628, width: 240, height: 64))
    }

    func testPanelWiderThanTheScreenIsPinnedToTheLeftEdge() {
        let visible = CGRect(x: 30, y: 0, width: 200, height: 400)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 30, y: 328, width: 240, height: 64))
    }

    func testSecondaryScreenAboveThePrimary() {
        // A screen stacked above the primary has a positive y origin in Cocoa coordinates.
        let visible = CGRect(x: -200, y: 900, width: 1920, height: 1055)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 640, y: 1883, width: 240, height: 64))
    }

    func testSmallMovementIsAClickNotADrag() {
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: .zero))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 8, y: 11)))
    }

    func testMovementAtOrBeyondThresholdIsADrag() {
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: -2, y: -3)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 620)))
    }

    func testDraggedOriginMovesByThePointerDelta() {
        let origin = CGPoint(x: 600, y: 803)
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 700, y: 830), to: CGPoint(x: 650, y: 800)),
                       CGPoint(x: 550, y: 773))
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)),
                       origin)
    }
}
