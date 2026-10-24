import XCTest
@testable import Tofu

final class CompanionLayoutTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testPanelSitsInBottomRightCornerInsideMargin() {
        let frame = CompanionLayout.frame(size: CompanionLayout.panelSize, visible: visible)
        XCTAssertEqual(frame.maxX, visible.maxX - CompanionLayout.margin)
        XCTAssertEqual(frame.minY, visible.minY + CompanionLayout.margin)
        XCTAssertEqual(frame.size, CompanionLayout.panelSize)
    }

    func testUsesVisibleFrameOriginForOffsetScreens() {
        let offset = CGRect(x: 100, y: 50, width: 800, height: 600)
        let frame = CompanionLayout.frame(size: CompanionLayout.panelSize, visible: offset)
        XCTAssertEqual(frame.maxX, offset.maxX - CompanionLayout.margin)
        XCTAssertEqual(frame.minY, offset.minY + CompanionLayout.margin)
    }

    func testPanelIsTallEnoughForBubbleAndMoss() {
        XCTAssertGreaterThanOrEqual(CompanionLayout.panelSize.height,
                                    CompanionLayout.portraitSize.height + CompanionLayout.bubbleHeight)
        XCTAssertGreaterThanOrEqual(CompanionLayout.panelSize.width, CompanionLayout.portraitSize.width)
    }
}
