import XCTest
@testable import Tofu

/// Pure rules behind the mini timer's ✕ and the end-of-session summary.
final class LockedUITests: XCTestCase {
    private let panel = MiniTimerLayout.panelSize

    // MARK: Mini timer ✕ hit area

    func testCloseHitRectSitsAtTheTrailingEdgeAndIsVerticallyCentered() {
        let rect = MiniTimerLayout.closeHitRect(in: panel)
        XCTAssertEqual(rect, CGRect(x: 250, y: 13, width: 38, height: 38))
        XCTAssertEqual(rect.midY, panel.height / 2)
    }

    func testPointsOnTheCrossAreCloseHits() {
        // The ✕ itself is 22 pt, centered at x = 296 - 16 - 11 = 269.
        XCTAssertTrue(MiniTimerLayout.isCloseHit(CGPoint(x: 269, y: 32), in: panel))
        XCTAssertTrue(MiniTimerLayout.isCloseHit(CGPoint(x: 258, y: 21), in: panel))
        XCTAssertTrue(MiniTimerLayout.isCloseHit(CGPoint(x: 280, y: 43), in: panel))
    }

    func testPointsOnTheBodyAreNotCloseHits() {
        XCTAssertFalse(MiniTimerLayout.isCloseHit(CGPoint(x: 20, y: 32), in: panel))
        XCTAssertFalse(MiniTimerLayout.isCloseHit(CGPoint(x: 120, y: 32), in: panel))
        XCTAssertFalse(MiniTimerLayout.isCloseHit(CGPoint(x: 150, y: 32), in: panel))
        // Just outside the padded target.
        XCTAssertFalse(MiniTimerLayout.isCloseHit(CGPoint(x: 249, y: 32), in: panel))
        XCTAssertFalse(MiniTimerLayout.isCloseHit(CGPoint(x: 269, y: 5), in: panel))
    }

    func testRequestEndNotificationNameIsStable() {
        XCTAssertEqual(Notification.Name.tofuRequestEnd.rawValue, "tofu.requestEnd")
    }

    // MARK: Session summary text

    func testOutcomeText() {
        XCTAssertEqual(SessionSummaryText.outcome(.completed), "Completed")
        XCTAssertEqual(SessionSummaryText.outcome(.bailed), "Bailed")
        XCTAssertEqual(SessionSummaryText.outcome(.interrupted), "Interrupted")
        XCTAssertEqual(SessionSummaryText.outcome(nil), "Ended")
    }

    func testGoalTextOnlyInGoalMode() {
        XCTAssertNil(SessionSummaryText.goal(.open))
        XCTAssertEqual(SessionSummaryText.goal(.goal(minutes: 50)), "50m")
        XCTAssertEqual(SessionSummaryText.goal(.goal(minutes: 90)), "1h 30m")
    }

    func testSummaryIsPresentedForCompletedAndBailedOnly() {
        XCTAssertFalse(SessionSummaryText.shouldPresent(nil))
        XCTAssertTrue(SessionSummaryText.shouldPresent(session(.completed)))
        XCTAssertTrue(SessionSummaryText.shouldPresent(session(.bailed)))
        XCTAssertFalse(SessionSummaryText.shouldPresent(session(.interrupted)))
        XCTAssertFalse(SessionSummaryText.shouldPresent(session(nil)))
    }

    func testMarkdownRecapFormatting() {
        var sess = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 50),
                           start: Date(timeIntervalSince1970: 0),
                           end: Date(timeIntervalSince1970: 3000),
                           blockedAttempts: 2, closedTabs: 1, outcome: .completed,
                           parkedThoughts: ["Check cache invalidation", "Email TA"])
        sess.notes = "Completed exercise 4.1"
        let priority = Priority(title: "MP3 AST Visitor", isDone: true)

        let recap = SessionSummaryText.markdownRecap(session: sess, priority: priority)
        XCTAssertTrue(recap.contains("### 🎯 Focus Block: CS128 (Completed)"))
        XCTAssertTrue(recap.contains("- **Duration:** 50m (Goal: 50m)"))
        XCTAssertTrue(recap.contains("- **Active Focus Priority:** MP3 AST Visitor ✓"))
        XCTAssertTrue(recap.contains("- **Shield Interventions:** 2 apps blocked · 1 tabs closed"))
        XCTAssertTrue(recap.contains("- **Notes & Reflection:** Completed exercise 4.1"))
        XCTAssertTrue(recap.contains("- **Parked Thoughts:**"))
        XCTAssertTrue(recap.contains("  - Check cache invalidation"))
        XCTAssertTrue(recap.contains("  - Email TA"))
    }

    func testDailyGoalProgressSnapshotCountsCompletedDaySessions() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let current = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 60),
                              start: base, end: base.addingTimeInterval(3600), outcome: .completed)
        let earlier = Session(subjectID: UUID(), subjectName: "Math", mode: .goal(minutes: 60),
                              start: base.addingTimeInterval(-7200), end: base.addingTimeInterval(-3600), outcome: .completed)
        let bailed = Session(subjectID: UUID(), subjectName: "Other", mode: .open,
                             start: base.addingTimeInterval(-10800), end: base.addingTimeInterval(-9000), outcome: .bailed)

        let snap = SessionSummaryText.dailyGoalProgress(
            for: current,
            allSessions: [earlier, bailed, current],
            dailyTargetMinutes: 120
        )

        XCTAssertEqual(snap.dayTotalSeconds, 7200, accuracy: 0.1)
        XCTAssertEqual(snap.percent, 100)
        XCTAssertTrue(snap.isMet)
    }

    private func session(_ outcome: SessionOutcome?) -> Session {
        Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                start: Date(timeIntervalSince1970: 0), outcome: outcome)
    }
}
