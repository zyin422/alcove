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

    func testASecondDocumentWindowIsClosedAndTheOriginalStays() {
        let windows = [
            MainWindowCandidate(id: "main", isPanel: false, isBorderless: false, canBecomeMain: true, isSheet: false, title: "Tofu"),
            MainWindowCandidate(id: "extra", isPanel: false, isBorderless: false, canBecomeMain: true, isSheet: false, title: "Tofu"),
            MainWindowCandidate(id: "spirit", isPanel: true, isBorderless: true, canBecomeMain: false, isSheet: false, title: ""),
            MainWindowCandidate(id: "settings", isPanel: false, isBorderless: false, canBecomeMain: true, isSheet: false, title: "Settings"),
        ]
        XCTAssertEqual(MainWindowPolicy.windowsToClose(windows, keeping: "main"), ["extra"])
    }

    func testOneWindowAndAMissingOriginalCloseNothing() {
        let only = MainWindowCandidate(id: "main", isPanel: false, isBorderless: false, canBecomeMain: true, isSheet: false, title: "Tofu")
        XCTAssertEqual(MainWindowPolicy.windowsToClose([only], keeping: "main"), [])
        XCTAssertEqual(MainWindowPolicy.windowsToClose([], keeping: nil), [])
    }

    func testCenteredFrameShrinksToASmallScreen() {
        let visible = CGRect(x: 0, y: 25, width: 800, height: 500)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 0, y: 25, width: 800, height: 500))
    }

    func testDayFocusProgressCombinesCompletedTodayAndActiveElapsed() {
        let cal = Calendar.current
        let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12, minute: 0))!
        let earlierToday = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9, minute: 0))!
        let subID = UUID()

        let prior = Session(subjectID: subID, subjectName: "CS128", mode: .open,
                            start: earlierToday, end: earlierToday.addingTimeInterval(90 * 60), outcome: .completed)
        let bailed = Session(subjectID: subID, subjectName: "CS128", mode: .open,
                             start: earlierToday, end: earlierToday.addingTimeInterval(30 * 60), outcome: .bailed)

        let midSession = LockedLayout.dayFocusProgress(sessions: [prior, bailed], activeElapsed: 30 * 60, targetMinutes: 120, now: noon, calendar: cal)
        XCTAssertEqual(midSession.focusedSeconds, 120 * 60, accuracy: 0.1)
        XCTAssertEqual(midSession.targetSeconds, 120 * 60, accuracy: 0.1)
        XCTAssertTrue(midSession.metGoal)

        let early = LockedLayout.dayFocusProgress(sessions: [prior], activeElapsed: 10 * 60, targetMinutes: 120, now: noon, calendar: cal)
        XCTAssertFalse(early.metGoal)
    }
}
