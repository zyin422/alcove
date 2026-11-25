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

    func testMenuBarStatusSummaryPrioritizesBreakSessionCountdownThenDailyTotal() {
        let onGrace = MenuBarStatusSummary.label(
            isLocked: true, subjectName: "CS128", gracePassRemaining: 95,
            breakRemaining: 125, sessionRemaining: 1800, sessionElapsed: 600,
            forceCountdownRemaining: 300, todayFocusedSeconds: 3600
        )
        XCTAssertEqual(onGrace.title, "Pass 01:35")
        XCTAssertEqual(onGrace.systemImage, "shield.lefthalf.filled")

        let onBreak = MenuBarStatusSummary.label(
            isLocked: true, subjectName: "CS128",
            breakRemaining: 125, sessionRemaining: 1800, sessionElapsed: 600,
            forceCountdownRemaining: 300, todayFocusedSeconds: 3600
        )
        XCTAssertEqual(onBreak.title, "Break 02:05")
        XCTAssertEqual(onBreak.systemImage, "cup.and.saucer.fill")

        let inBlock = MenuBarStatusSummary.label(
            isLocked: true, subjectName: "CS128",
            breakRemaining: nil, sessionRemaining: 1500, sessionElapsed: 300,
            forceCountdownRemaining: 300, todayFocusedSeconds: 3600
        )
        XCTAssertEqual(inBlock.title, "CS128 · 25:00")
        XCTAssertEqual(inBlock.systemImage, "lock.shield.fill")

        let countdown = MenuBarStatusSummary.label(
            isLocked: false, subjectName: nil,
            breakRemaining: nil, sessionRemaining: nil, sessionElapsed: 0,
            forceCountdownRemaining: 90, todayFocusedSeconds: 3600
        )
        XCTAssertEqual(countdown.title, "Next block 01:30")
        XCTAssertEqual(countdown.systemImage, "timer")

        let idleWithFocus = MenuBarStatusSummary.label(
            isLocked: false, subjectName: nil,
            breakRemaining: nil, sessionRemaining: nil, sessionElapsed: 0,
            forceCountdownRemaining: nil, todayFocusedSeconds: 5400
        )
        XCTAssertEqual(idleWithFocus.title, "Tofu · 1h 30m")
    }

    func testLockInWorkspaceSummaryDescribesSetupCleanly() {
        let xcode = AllowedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let subject = Subject(
            name: "CS128",
            preset: .split,
            sites: ["swift.org"],
            allowedApps: [xcode],
            extraDomains: ["cppreference.com"],
            slots: [
                SetupSlot(kind: .website, urls: ["https://swift.org", "https://docs.swift.org"]),
                SetupSlot(kind: .app, app: xcode, folder: "~/cs128"),
            ],
            browser: .arc,
            unusedApps: .quit
        )

        let info = LockInWorkspaceSummary.describe(subject: subject)
        XCTAssertEqual(info.layoutLabel, LayoutPreset.split.title)
        XCTAssertEqual(info.browserTitle, "Arc")
        XCTAssertEqual(info.urlCount, 2)
        XCTAssertEqual(info.appNames, ["Xcode"])
        XCTAssertEqual(info.unusedPolicyLabel, "Quit other apps")
        XCTAssertEqual(info.trustedDomains, ["cppreference.com", "swift.org"])

        let summaryText = LockInWorkspaceSummary.clipboardText(subject: subject)
        XCTAssertTrue(summaryText.contains("Setup: CS128"))
        XCTAssertTrue(summaryText.contains("Apps: Xcode"))
        XCTAssertTrue(summaryText.contains("cppreference.com"))
    }

    func testFollowUpPriorityParsesNoteWithFallbackSubject() {
        let cs = Subject(name: "CS128")
        let math = Subject(name: "MATH241")

        let created = SessionSummaryText.followUpPriority(
            from: "Finish integration problem 45m",
            fallbackSubjectID: math.id,
            subjects: [cs, math]
        )

        XCTAssertEqual(created?.title, "Finish integration problem")
        XCTAssertEqual(created?.estimatedMinutes, 45)
        XCTAssertEqual(created?.subjectID, math.id)
        XCTAssertNil(SessionSummaryText.followUpPriority(from: "   \n ", fallbackSubjectID: cs.id, subjects: [cs]))
    }

    func testRecentSessionsReturnsLatestCompletedSessionsInDescendingOrder() {
        let id = UUID()
        let otherID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s1 = Session(subjectID: id, subjectName: "CS128", mode: .open, start: t0, end: t0.addingTimeInterval(600), outcome: .completed)
        let s2 = Session(subjectID: id, subjectName: "CS128", mode: .open, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(4200), outcome: .bailed)
        let s3 = Session(subjectID: id, subjectName: "CS128", mode: .open, start: t0.addingTimeInterval(7200), end: t0.addingTimeInterval(9000), outcome: .completed)
        let s4 = Session(subjectID: otherID, subjectName: "Math", mode: .open, start: t0.addingTimeInterval(9500), end: t0.addingTimeInterval(10000), outcome: .completed)

        let recent = SubjectTelemetry.recentSessions(subjectID: id, sessions: [s1, s2, s3, s4])
        XCTAssertEqual(recent.map(\.id), [s3.id, s1.id])

        let telemetry = SubjectTelemetry.calculate(subjectID: id, sessions: [s1, s2, s3, s4], dayPlans: [], now: t0.addingTimeInterval(8000))
        XCTAssertEqual(telemetry.totalSeconds, 2400, accuracy: 0.1)
        XCTAssertEqual(telemetry.thisWeekSeconds, 2400, accuracy: 0.1)
    }

    func testUnlockTimeLabelFormatsFutureTimestampCleanly() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(LockedLayout.unlockTimeLabel(remaining: nil, now: base))
        XCTAssertNil(LockedLayout.unlockTimeLabel(remaining: 0, now: base))
        let label = LockedLayout.unlockTimeLabel(remaining: 3000, now: base)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.hasPrefix("Unlocks ") == true)
    }

    private func session(_ outcome: SessionOutcome?) -> Session {
        Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                start: Date(timeIntervalSince1970: 0), outcome: outcome)
    }
}
