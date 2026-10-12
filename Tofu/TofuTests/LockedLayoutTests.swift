import XCTest
@testable import Tofu

final class LockedLayoutTests: XCTestCase {
    func testWindowSizeIs900By600() {
        XCTAssertEqual(LockedLayout.windowSize, CGSize(width: 900, height: 600))
    }

    func testTimerFontIsLimitedByWidthInATallZone() {
        // Thirds app zone on a 1440x875 visible frame: 480 wide.
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 480, height: 700)), 96)
    }

    func testTimerFontIsLimitedByHeightInAWideZone() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 900, height: 300)), 126, accuracy: 0.0001)
    }

    func testTimerFontUsesTheSmallerOfBothLimits() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 1000, height: 600)), 200)
    }

    func testTimerFontNeverDropsBelowOnePoint() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: .zero), 1)
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: -50, height: 100)), 1)
    }

    func testProgressIsElapsedOverGoal() {
        XCTAssertEqual(LockedLayout.progress(elapsed: 750, goal: 1500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LockedLayout.progress(elapsed: 0, goal: 1500), 0)
    }

    func testProgressIsClampedToZeroAndOne() {
        XCTAssertEqual(LockedLayout.progress(elapsed: -5, goal: 1500), 0)
        XCTAssertEqual(LockedLayout.progress(elapsed: 2000, goal: 1500), 1)
        XCTAssertEqual(LockedLayout.progress(elapsed: 10, goal: 0), 1)
    }

    func testCountersText() {
        XCTAssertEqual(LockedLayout.countersText(blocked: 0, tabs: 0), "0 apps blocked · 0 tabs closed")
        XCTAssertEqual(LockedLayout.countersText(blocked: 3, tabs: 2), "3 apps blocked · 2 tabs closed")
        XCTAssertEqual(LockedLayout.countersText(blocked: 1, tabs: 1), "1 app blocked · 1 tab closed")
    }

    func testGoalCaption() {
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 25 * 60), "goal 25m")
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 50 * 60), "goal 50m")
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 90 * 60), "goal 1h 30m")
    }

    func testCenteredFrameOnALargeScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 270, y: 137, width: 900, height: 600))
    }

    func testCenteredFrameFollowsTheVisibleFrameOrigin() {
        let visible = CGRect(x: 100, y: 40, width: 1200, height: 800)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 250, y: 140, width: 900, height: 600))
    }

    func testCenteredFrameShrinksToASmallScreen() {
        let visible = CGRect(x: 0, y: 25, width: 800, height: 500)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 0, y: 25, width: 800, height: 500))
    }
}
