import XCTest
@testable import Tofu

@MainActor
final class SessionEngineTests: XCTestCase {
    private let ownID = "com.tofu.app"
    private let template = "I give up on {subject}"

    /// CS128 with one extra allowed app and a deprecated extra domain (the tab watch must ignore it);
    /// site count follows the preset.
    private func makeSubject(_ preset: LayoutPreset = .split) -> Subject {
        let sites = preset.siteCount == 2
            ? ["https://cs128.org/schedule", "https://docs.python.org/3/"]
            : ["https://cs128.org/schedule"]
        return Subject(name: "CS128", preset: preset, sites: sites,
                       allowedApps: [AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")],
                       extraDomains: ["piazza.com"])
    }

    /// Lets main-actor tasks spawned by the engine (the goal auto-finish) run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: Lock in

    func testStartHidesEverythingExceptAllowedApps() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.workspace.hideCalls,
                       [[ownID, "com.google.Chrome", "com.apple.finder", "com.apple.systempreferences", "com.microsoft.VSCode"]])
        XCTAssertTrue(h.engine.isLocked)
        XCTAssertEqual(h.engine.subject?.name, "CS128")
        XCTAssertEqual(h.engine.session?.subjectName, "CS128")
        XCTAssertEqual(h.engine.session?.start, h.clock.now)
        XCTAssertNil(h.engine.session?.end)
        XCTAssertNil(h.engine.remaining)
        XCTAssertFalse(h.engine.needsGiveUpPhrase)
    }

    func testStartReportsNewSession() async {
        let h = EngineHarness()
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.subjectName, "CS128")
        XCTAssertNil(changes.first?.end)
        XCTAssertEqual(changes.first?.id, h.engine.session?.id)
    }

    func testSplitPresetTilesTwoChromeHalvesAndShowsMiniTimer() async {
        let h = EngineHarness()
        let subject = makeSubject(.split)
        await h.engine.start(subject: subject, mode: .open, displayName: "Alex")

        XCTAssertEqual(h.chrome.preparedSites, subject.sites)
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 0, top: 0, right: 500, bottom: 800),
                                                 ChromeBounds(left: 500, top: 0, right: 1000, bottom: 800)])
        XCTAssertEqual(h.presenter.entered, [nil])
    }

    func testThirdsPresetGivesAppTheLeftThird() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(.thirds), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.presenter.entered, [CGRect(x: 0, y: 0, width: 333, height: 800)])
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 333, top: 0, right: 666, bottom: 800),
                                                 ChromeBounds(left: 666, top: 0, right: 1000, bottom: 800)])
    }

    func testMainSidePresetGivesAppTheRightThirty() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(.mainSide), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.presenter.entered, [CGRect(x: 700, y: 0, width: 300, height: 800)])
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 0, top: 0, right: 700, bottom: 800)])
    }

    func testWithoutScreenOpensSitesUntiledAndShowsMiniTimer() async {
        let chrome = FakeChrome()
        let presenter = FakePresenter()
        let engine = SessionEngine(workspace: FakeWorkspace(), blocker: FakeBlocker(), chrome: chrome,
                                   toaster: FakeToaster(), announcer: FakeAnnouncer(), ownBundleID: ownID,
                                   startsTimers: false)
        engine.presenter = presenter
        await engine.start(subject: makeSubject(.thirds), mode: .open, displayName: "Alex")

        XCTAssertEqual(chrome.preparedSites.count, 2)
        XCTAssertEqual(chrome.preparedBounds, [])
        XCTAssertEqual(presenter.entered, [nil])
        XCTAssertTrue(engine.isLocked)
    }

    func testStartBeginsBlockingAndTabWatchAndAnnounces() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.blocker.startedWith,
                       [ownID, "com.google.Chrome", "com.apple.finder", "com.apple.systempreferences", "com.microsoft.VSCode"])
        XCTAssertEqual(h.chrome.watchedSubject, "CS128")
        XCTAssertEqual(h.chrome.watchedSites, ["https://cs128.org/schedule", "https://docs.python.org/3/"])
        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128**"])
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testGoalModeStartMessageIncludesGoal() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128** (goal 25m)"])
        XCTAssertEqual(h.engine.remaining, 1500)
        XCTAssertTrue(h.engine.needsGiveUpPhrase)
    }

    func testSecondStartIsIgnoredWhileLocked() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        let other = Subject(name: "MATH241", preset: .full, sites: ["https://math.illinois.edu"])
        await h.engine.start(subject: other, mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.engine.session?.subjectName, "CS128")
        XCTAssertEqual(h.workspace.hideCalls.count, 1)
        XCTAssertEqual(h.presenter.entered.count, 1)
        XCTAssertEqual(h.announcer.messages.count, 1)
    }

    // MARK: Lock-in / ended hooks

    func testOnLockedInRunsOnceAfterEverythingIsSetUp() async {
        let h = EngineHarness()
        var subjects: [String] = []
        var watched: [String?] = []
        var blocking: [Bool] = []
        var announced: [Int] = []
        h.engine.onLockedIn = { subject in
            subjects.append(subject.name)
            watched.append(h.chrome.watchedSubject)
            blocking.append(h.blocker.startedWith != nil)
            announced.append(h.announcer.messages.count)
        }

        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(subjects, ["CS128"])
        XCTAssertEqual(watched, ["CS128"], "the tab watch is already running")
        XCTAssertEqual(blocking, [true])
        XCTAssertEqual(announced, [1], "the start announcement is already out")
        XCTAssertTrue(h.engine.isLocked)
    }

    func testOnLockedInIsNotRepeatedByAnIgnoredSecondStart() async {
        let h = EngineHarness()
        var count = 0
        h.engine.onLockedIn = { _ in count += 1 }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(count, 1)
    }

    func testOnLockedInStillRunsWhenChromeCannotBeScripted() async {
        let h = EngineHarness()
        h.chrome.prepareResult = .automationDenied
        var count = 0
        h.engine.onLockedIn = { _ in count += 1 }

        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(count, 1)
    }

    func testOnLockedInDoesNotRunWhenTheSessionEndedWhileChromeWasPrepared() async {
        let h = EngineHarness()
        h.chrome.onPrepare = { h.engine.terminateNow() }
        var lockedIn = 0
        var ended = 0
        h.engine.onLockedIn = { _ in lockedIn += 1 }
        h.engine.onEnded = { ended += 1 }

        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(lockedIn, 0)
        XCTAssertEqual(ended, 1)
    }

    func testOnEndedRunsAfterFinishBailAndTerminate() async {
        let h = EngineHarness()
        var ended: [Bool] = []   // isLocked at the time of each call
        h.engine.onEnded = { ended.append(h.engine.isLocked) }

        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        await h.engine.finish()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")
        await h.engine.bail()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.engine.terminateNow()

        XCTAssertEqual(ended, [false, false, false], "each end reports once, with the engine already idle")
    }

    func testOnEndedRunsWhenTheGoalIsReached() async {
        let h = EngineHarness()
        var ended = 0
        h.engine.onEnded = { ended += 1 }
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 1), displayName: "Alex")

        h.clock.advance(61)
        h.engine.tick()
        await settle()

        XCTAssertEqual(ended, 1)
    }

    func testOnEndedDoesNotRunWhileIdle() async {
        let h = EngineHarness()
        var ended = 0
        h.engine.onEnded = { ended += 1 }

        h.engine.terminateNow()
        await h.engine.finish()
        await h.engine.bail()

        XCTAssertEqual(ended, 0)
    }

    func testOnEndedRunsOnlyOncePerSession() async {
        let h = EngineHarness()
        var ended = 0
        h.engine.onEnded = { ended += 1 }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        await h.engine.finish()
        await h.engine.finish()
        h.engine.terminateNow()

        XCTAssertEqual(ended, 1)
    }

    // MARK: Chrome failures

    func testChromeErrorsShowToastAndSessionContinues() async {
        let cases: [(ChromeError, String)] = [
            (.notInstalled, "Google Chrome not found — sites not opened"),
            (.automationDenied, "Allow Chrome control in System Settings › Privacy & Security › Automation"),
            (.profileNotReady, "Chrome wasn't ready — sites not opened"),
            (.scriptFailed("boom"), "Chrome error: boom"),
        ]
        for (error, expected) in cases {
            let h = EngineHarness()
            h.chrome.prepareResult = error
            await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

            XCTAssertEqual(h.toaster.messages, [expected])
            XCTAssertTrue(h.engine.isLocked)
            XCTAssertNotNil(h.blocker.startedWith)
            XCTAssertEqual(h.announcer.messages.count, 1)
        }
    }

    func testTabWatchSkippedWhenChromeCannotBeScripted() async {
        let denied = EngineHarness()
        denied.chrome.prepareResult = .automationDenied
        await denied.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertNil(denied.chrome.watchedSubject)

        let missing = EngineHarness()
        missing.chrome.prepareResult = .notInstalled
        await missing.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertNil(missing.chrome.watchedSubject)

        let slow = EngineHarness()
        slow.chrome.prepareResult = .profileNotReady
        await slow.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertEqual(slow.chrome.watchedSubject, "CS128")
        XCTAssertEqual(slow.chrome.watchedSites, ["https://cs128.org/schedule", "https://docs.python.org/3/"])
    }

    // MARK: During the session

    func testBlockedAttemptCountsToastsAndPersists() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")

        XCTAssertEqual(h.engine.session?.blockedAttempts, 1)
        XCTAssertEqual(h.toaster.messages, ["🔒 Discord is blocked during CS128"])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last?.blockedAttempts, 1)
    }

    func testClosedTabCountsToastsAndPersists() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.chrome.simulateTabClosed("youtube.com")

        XCTAssertEqual(h.engine.session?.closedTabs, 1)
        XCTAssertEqual(h.toaster.messages, ["Closed youtube.com — not relevant to CS128"])
        XCTAssertEqual(changes.last?.closedTabs, 1)
    }

    func testHeartbeatEvery30Seconds() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        let start = h.clock.now
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.clock.advance(29)
        h.engine.tick()
        XCTAssertEqual(h.engine.now, h.clock.now)
        XCTAssertEqual(h.engine.elapsed, 29, accuracy: 0.001)
        XCTAssertEqual(h.engine.session?.lastHeartbeat, start)
        XCTAssertTrue(changes.isEmpty)

        h.clock.advance(2)
        h.engine.tick()
        XCTAssertEqual(h.engine.elapsed, 31, accuracy: 0.001)
        XCTAssertEqual(h.engine.session?.lastHeartbeat, h.clock.now)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last?.lastHeartbeat, h.clock.now)
        XCTAssertNil(changes.last?.end)
    }

    // MARK: Goal countdown

    func testGoalCompletesExactlyOnceWhenCountdownReachesZero() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 1), displayName: "Alex")
        XCTAssertTrue(h.engine.needsGiveUpPhrase)
        XCTAssertEqual(h.engine.remaining, 60)

        h.clock.advance(30)
        h.engine.tick()
        XCTAssertEqual(h.engine.remaining, 30)
        XCTAssertTrue(h.engine.needsGiveUpPhrase)

        h.clock.advance(31)
        h.engine.tick()
        h.engine.tick()
        XCTAssertTrue(h.engine.goalReached)
        XCTAssertEqual(h.engine.remaining, 0)
        XCTAssertFalse(h.engine.needsGiveUpPhrase)

        await settle()
        XCTAssertFalse(h.engine.isLocked)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(h.announcer.messages, [
            "🔒 **Alex** is locked in on **CS128** (goal 1m)",
            "✅ **Alex** locked in on **CS128** for **1m** · tried other apps **0×** · closed **0** tabs",
        ])
        XCTAssertEqual(h.toaster.messages, ["Saved: 1m on CS128"])
        XCTAssertEqual(h.presenter.exitCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)

        // Late ticks and a late finish() change nothing.
        h.clock.advance(5)
        h.engine.tick()
        await h.engine.finish()
        await settle()
        XCTAssertEqual(h.announcer.messages.filter { $0.hasPrefix("✅") }.count, 1)
        XCTAssertEqual(h.announcer.messages.count, 2)
        XCTAssertEqual(h.workspace.unhideCalls.count, 1)
    }

    func testBailAfterGoalCountsAsCompleted() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 1), displayName: "Alex")
        h.clock.advance(61)

        await h.engine.bail()

        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **1m** · tried other apps **0×** · closed **0** tabs")
    }

    // MARK: Give-up phrase

    func testGiveUpPhraseIgnoresCaseAndSurroundingWhitespace() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.engine.giveUpPhrase(template: template), "I give up on CS128")
        XCTAssertEqual(h.engine.giveUpPhrase(template: template, name: "Calc241"), "I give up on Calc241")
        XCTAssertTrue(h.engine.phraseMatches("I give up on Calc241", template: template, name: "Calc241"))
        XCTAssertFalse(h.engine.phraseMatches("I give up on CS128", template: template, name: "Calc241"))
        XCTAssertTrue(h.engine.phraseMatches("  i GIVE up on cs128 \n", template: template))
        XCTAssertTrue(h.engine.phraseMatches("I give up on CS128", template: template))
        XCTAssertFalse(h.engine.phraseMatches("I give up", template: template))
        XCTAssertFalse(h.engine.phraseMatches("I give up on CS12", template: template))
        XCTAssertFalse(h.engine.phraseMatches("", template: template))
    }

    // MARK: Ending

    func testBailInGoalModePostsBailedAndRestoresHiddenApps() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.hnc.Discord"]
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        h.clock.advance(600)

        await h.engine.bail()

        XCTAssertFalse(h.engine.isLocked)
        XCTAssertNil(h.engine.subject)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .bailed)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(h.engine.lastEnded?.blockedAttempts, 1)
        XCTAssertEqual(h.workspace.unhideCalls, [["com.hnc.Discord"]])
        XCTAssertEqual(h.chrome.restoreCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.presenter.exitCount, 1)
        XCTAssertEqual(h.toaster.messages.last, "Saved: 10m on CS128")
        XCTAssertEqual(h.announcer.messages.count, 2)
        XCTAssertEqual(h.announcer.messages.last,
                       DiscordMessages.bailed(name: "Alex", subject: "CS128", duration: 600,
                                              goalMinutes: 25, attempts: 1))
        XCTAssertTrue(h.announcer.messages.last?.hasPrefix("🏳️") ?? false)
    }

    func testFinishInOpenModePostsCompletedWithTotals() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.apple.Notes"]
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        h.blocker.simulateBlocked("com.apple.Notes", name: "Notes")
        h.chrome.simulateTabClosed("youtube.com")
        h.clock.advance(4800)

        await h.engine.finish()

        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **1h 20m** · tried other apps **2×** · closed **1** tabs")
        XCTAssertEqual(h.toaster.messages.last, "Saved: 1h 20m on CS128")
        XCTAssertEqual(h.workspace.unhideCalls, [["com.apple.Notes"]])
        XCTAssertEqual(changes.last?.outcome, .completed)
        XCTAssertEqual(changes.last?.end, h.clock.now)
        XCTAssertEqual(changes.last?.lastHeartbeat, h.clock.now)
        XCTAssertEqual(h.engine.lastEnded, changes.last)
        XCTAssertEqual(h.engine.lastEnded?.duration ?? 0, 4800, accuracy: 0.001)

        // Callbacks after the end are ignored.
        let toastCount = h.toaster.messages.count
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        XCTAssertEqual(h.toaster.messages.count, toastCount)
    }

    func testBailInOpenModeBehavesLikeFinish() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.clock.advance(720)

        await h.engine.bail()

        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **12m** · tried other apps **0×** · closed **0** tabs")
    }

    func testTerminateNowEndsInterruptedWithoutAnnouncing() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.hnc.Discord", "com.apple.Notes"]
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 50), displayName: "Alex")
        h.clock.advance(120)

        h.engine.terminateNow()

        XCTAssertFalse(h.engine.isLocked)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .interrupted)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(changes.last?.outcome, .interrupted)
        XCTAssertEqual(h.workspace.unhideCalls, [["com.hnc.Discord", "com.apple.Notes"]])
        XCTAssertEqual(h.chrome.restoreCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128** (goal 50m)"])

        // A later finish is a no-op: nothing is unhidden twice and nothing is posted.
        await h.engine.finish()
        XCTAssertEqual(h.announcer.messages.count, 1)
        XCTAssertEqual(h.workspace.unhideCalls.count, 1)
    }

    func testEndingWhileIdleDoesNothing() async {
        let h = EngineHarness()
        h.engine.terminateNow()
        await h.engine.finish()
        await h.engine.bail()
        h.engine.tick()

        XCTAssertNil(h.engine.lastEnded)
        XCTAssertTrue(h.workspace.unhideCalls.isEmpty)
        XCTAssertEqual(h.blocker.stopCount, 0)
        XCTAssertTrue(h.announcer.messages.isEmpty)
        XCTAssertEqual(h.engine.elapsed, 0)
    }
}
