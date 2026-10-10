import AppKit
import XCTest
@testable import Accountabilibrosis

final class ScreenGeometryTests: XCTestCase {
    func testFlipsTheYAxisAgainstThePrimaryScreenHeight() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0, y: 0, width: 840, height: 1020),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 30, right: 840, bottom: 1050))
    }

    func testNonZeroOrigin() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 100, y: 50, width: 600, height: 900),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 100, top: 100, right: 700, bottom: 1000))
    }

    func testRoundsToTheNearestWholePoint() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0.4, y: 10.6, width: 333.3, height: 500.2),
                                                 primaryHeight: 1000)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 489, right: 334, bottom: 989))
    }

    func testScreenAboveThePrimaryGetsNegativeTop() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0, y: 1050, width: 1920, height: 1080),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: -1080, right: 1920, bottom: 0))
    }

    func testNonFiniteInputDoesNotTrap() {
        let bounds = ScreenGeometry.chromeBounds(for: .null, primaryHeight: .nan)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 0, right: 0, bottom: 0))
    }

    func testSplitLayoutConvertsToChromeBounds() {
        // 1440x900 primary screen, 25 pt menu bar, Dock hidden: visible frame is 1440x875 at the origin.
        let layout = LayoutEngine.layout(.split, in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        let bounds = layout.chromeFrames.map { ScreenGeometry.chromeBounds(for: $0, primaryHeight: 900) }
        XCTAssertEqual(bounds, [
            ChromeBounds(left: 0, top: 25, right: 720, bottom: 900),
            ChromeBounds(left: 720, top: 25, right: 1440, bottom: 900),
        ])
    }

    @MainActor func testLiveScreenQueriesAgreeWithNSScreen() {
        if NSScreen.screens.isEmpty {
            XCTAssertNil(ScreenGeometry.mainVisibleFrame())
            XCTAssertEqual(ScreenGeometry.primaryHeight(), 0)
        } else {
            XCTAssertEqual(ScreenGeometry.primaryHeight(), NSScreen.screens.first?.frame.height)
            let visible = ScreenGeometry.mainVisibleFrame()
            XCTAssertNotNil(visible)
            XCTAssertGreaterThan(visible?.width ?? 0, 0)
            XCTAssertGreaterThan(visible?.height ?? 0, 0)
        }
    }
}
