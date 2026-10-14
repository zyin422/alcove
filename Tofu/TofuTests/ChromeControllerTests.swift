import XCTest
@testable import Tofu

/// Exercises ChromeController.run with plain AppleScript that never talks to Chrome (or any other app).
@MainActor final class ChromeControllerTests: XCTestCase {
    func testRunReturnsTextResult() {
        XCTAssertEqual(ChromeController.run(#"return "hello""#), .success("hello"))
    }

    func testRunCoercesIntegerResultToText() {
        XCTAssertEqual(ChromeController.run("return 7"), .success("7"))
    }

    func testRunMapsErrorMinus1743ToAutomationDenied() {
        XCTAssertEqual(ChromeController.run(#"error "Not authorized" number -1743"#), .failure(.automationDenied))
    }

    func testRunMapsOtherErrorsToScriptFailedWithMessage() {
        XCTAssertEqual(ChromeController.run(#"error "boom" number 42"#), .failure(.scriptFailed("boom")))
    }

    func testRunReportsCompileErrorsAsScriptFailed() {
        guard case .failure(.scriptFailed(let message)) = ChromeController.run("set x to (") else {
            return XCTFail("expected .scriptFailed for a syntax error")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: openAll (prepare's per-site loop)

    /// Records every script handed to `openAll` and answers from `results` (missing key = success).
    private func runOpenAll(_ scripts: [String], results: [String: ChromeError]) async -> (ChromeError?, [String]) {
        var attempted: [String] = []
        let error = await ChromeController.openAll(scripts) { script in
            attempted.append(script)
            return results[script]
        }
        return (error, attempted)
    }

    func testOpenAllReturnsNilWhenEverySiteOpens() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: [:])
        XCTAssertNil(error)
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllKeepsOpeningRemainingSitesAfterProfileNotReady() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: ["a": .profileNotReady])
        XCTAssertEqual(error, .profileNotReady)
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllReturnsTheFirstErrorWhenSeveralSitesFail() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"],
                                                  results: ["b": .scriptFailed("first"), "c": .profileNotReady])
        XCTAssertEqual(error, .scriptFailed("first"))
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllStopsImmediatelyOnAutomationDenied() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: ["b": .automationDenied])
        XCTAssertEqual(error, .automationDenied)
        XCTAssertEqual(attempted, ["a", "b"])
    }

    func testOpenAllAutomationDeniedWinsOverEarlierSoftFailure() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"],
                                                  results: ["a": .profileNotReady, "b": .automationDenied])
        XCTAssertEqual(error, .automationDenied)
        XCTAssertEqual(attempted, ["a", "b"])
    }

    func testOpenAllStopsImmediatelyOnNotInstalled() async {
        let (error, attempted) = await runOpenAll(["a", "b"], results: ["a": .notInstalled])
        XCTAssertEqual(error, .notInstalled)
        XCTAssertEqual(attempted, ["a"])
    }

    func testOpenAllWithNoScriptsSucceeds() async {
        let (error, attempted) = await runOpenAll([], results: [:])
        XCTAssertNil(error)
        XCTAssertEqual(attempted, [])
    }

    // MARK: tab watch (fake Chrome, judge and prompter)

    /// Stands in for Chrome: answers `listTabs` from `tabs`, removes a tab when its close script runs, and logs everything.
    private final class ScriptLog {
        var tabs: [ChromeTab] = []
        var isRunning = true
        var listError: ChromeError?
        private(set) var scripts: [String] = []

        var closeScripts: [String] { scripts.filter { $0.contains("close (every tab") } }

        func run(_ source: String) -> Result<String, ChromeError> {
            scripts.append(source)
            if source == ChromeScripts.listTabs {
                if let listError { return .failure(listError) }
                let separator = String(ChromeScripts.fieldSeparator)
                let lines = tabs.map {
                    [$0.windowID.raw, String($0.tabIndex), $0.tabID.raw, $0.title, $0.url]
                        .joined(separator: separator)
                }
                return .success(lines.joined(separator: "\n") + "\n")
            }
            tabs.removeAll { source == ChromeScripts.closeTab(windowID: $0.windowID, tabID: $0.tabID) }
            return .success("")
        }
    }

    @MainActor private final class WatchHarness {
        let judge = FakeJudge()
        let prompter = FakePrompter()
        let asker = FakeAsker()
        let log = ScriptLog()
        let controller: ChromeController
        private(set) var closedHosts: [String] = []

        init(tabs: [ChromeTab]) {
            log.tabs = tabs
            let log = self.log
            controller = ChromeController(judge: judge, prompter: prompter,
                                          runScript: { log.run($0) }, chromeIsRunning: { log.isRunning })
            controller.onTabClosed = { [unowned self] host in self.closedHosts.append(host) }
            controller.asker = asker
        }

        func start() {
            controller.startTabWatch(subject: "CS128", studySites: ["https://cs128.org/schedule"])
        }
    }

    private func tab(_ url: String, id: Int, window: Int = 1, title: String = "") -> ChromeTab {
        ChromeTab(windowID: ScriptID(window), tabIndex: id, tabID: ScriptID(id), title: title, url: url)
    }

    /// Lets the tasks the controller spawned (judge calls, prompts) run.
    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    func testOffTaskVerdictClosesTheTabByIDAndReportsItsHost() async {
        let study = tab("https://cs128.org/schedule", id: 11)
        let reddit = tab("https://reddit.com/r/all", id: 22, title: "Reddit")
        let h = WatchHarness(tabs: [study, reddit])
        h.judge.verdicts[reddit.url] = .offTask
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.judge.judgedURLs, [reddit.url], "the study site is never judged")
        XCTAssertEqual(h.judge.judgedSubjects, ["CS128"])
        XCTAssertEqual(h.judge.judgedPages.first?.title, "Reddit")
        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 22)])
        XCTAssertEqual(h.closedHosts, ["reddit.com"])
    }

    func testRelevantVerdictKeepsTheTabAndIsNotAskedAgain() async {
        let video = tab("https://youtube.com/watch?v=lecture", id: 5)
        let h = WatchHarness(tabs: [video])
        h.judge.verdicts[video.url] = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        h.controller.pollTabs()
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.judge.judgedURLs, [video.url])
        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testTabIsNotJudgedAgainWhileTheFirstCheckIsStillRunning() async {
        let page = tab("https://example.org/post", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.holds = true
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.judge.judgedURLs, [page.url])
        XCTAssertEqual(h.judge.pendingCount, 1)
        h.judge.resolveNext(.relevant)
        await settle()
    }

    func testOffTaskURLThatReappearsIsClosedWithoutAskingTheJudgeAgain() async {
        let first = tab("https://reddit.com/r/all", id: 22)
        let h = WatchHarness(tabs: [first])
        h.judge.verdicts[first.url] = .offTask
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.closedHosts, ["reddit.com"])

        let again = tab("https://reddit.com/r/all", id: 30, window: 2)
        h.log.tabs = [again]
        h.controller.pollTabs()   // closes synchronously, no await needed

        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 22),
                                            ChromeScripts.closeTab(windowID: 2, tabID: 30)])
        XCTAssertEqual(h.closedHosts, ["reddit.com", "reddit.com"])
        XCTAssertEqual(h.judge.judgedURLs, [first.url])
    }

    func testOffTaskVerdictForATabThatIsAlreadyGoneClosesAndCountsNothing() async {
        let reddit = tab("https://reddit.com/r/all", id: 22)
        let h = WatchHarness(tabs: [reddit])
        h.judge.holds = true
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        h.log.tabs = []   // the user closed it while the check was running
        h.judge.resolveNext(.offTask)
        await settle()

        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testOffTaskVerdictForATabThatMovedOnToAnotherPageLeavesItAlone() async {
        let old = tab("https://reddit.com/r/all", id: 22)
        let h = WatchHarness(tabs: [old])
        h.judge.holds = true
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        h.log.tabs = [tab("https://cs128.org/schedule", id: 22)]   // same tab id, new address
        h.judge.resolveNext(.offTask)
        await settle()

        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testUnknownVerdictAsksOncePerHostAndNeededKeepsTheTabs() async {
        let a = tab("https://example.org/one", id: 5)
        let b = tab("https://example.org/two", id: 6)
        let h = WatchHarness(tabs: [a, b])
        h.judge.defaultVerdict = .unknown("no key")
        h.prompter.answers["example.org"] = true
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.prompter.asked, ["example.org"])
        XCTAssertEqual(h.prompter.askedSubjects, ["CS128"])
        XCTAssertEqual(h.judge.judgedURLs, [a.url, b.url], "no re-checks after the user said it is needed")
        XCTAssertEqual(h.log.closeScripts, [])
    }

    func testUnknownVerdictThenCloseTabClosesEveryTabOfTheHostOnTheNextPoll() async {
        let a = tab("https://example.org/one", id: 5)
        let b = tab("https://example.org/two", id: 6)
        let other = tab("https://other.org/", id: 7)
        let h = WatchHarness(tabs: [a, b, other])
        h.judge.defaultVerdict = .relevant
        h.judge.verdicts[a.url] = .unknown("offline")
        h.prompter.answers["example.org"] = false
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.log.closeScripts, [], "the answer is acted on by the next poll")

        h.controller.pollTabs()
        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 5),
                                            ChromeScripts.closeTab(windowID: 1, tabID: 6)])
        XCTAssertEqual(h.closedHosts, ["example.org", "example.org"])
        XCTAssertEqual(h.prompter.asked, ["example.org"])
    }

    func testOnlyOneQuestionIsOnScreenAtATime() async {
        let a = tab("https://a.org/", id: 5)
        let b = tab("https://b.org/", id: 6)
        let h = WatchHarness(tabs: [a, b])
        h.judge.defaultVerdict = .unknown("offline")
        h.prompter.holds = true
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.prompter.asked, ["a.org"])

        h.prompter.resolveNext(true)
        await settle()
        XCTAssertEqual(h.prompter.asked, ["a.org", "b.org"])

        h.prompter.resolveNext(false)
        await settle()
        h.controller.pollTabs()
        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 6)])
    }

    func testStoppingTheWatchIgnoresVerdictsThatArriveLate() async {
        let reddit = tab("https://reddit.com/r/all", id: 22)
        let h = WatchHarness(tabs: [reddit])
        h.judge.holds = true
        h.start()
        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.judge.pendingCount, 1)

        h.controller.stopTabWatch()
        h.judge.resolveNext(.offTask)
        await settle()

        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testStoppingTheWatchIgnoresAnswersThatArriveLate() async {
        let page = tab("https://example.org/post", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.defaultVerdict = .unknown("offline")
        h.prompter.holds = true
        h.start()
        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.prompter.pendingCount, 1)

        // The question from the old watch is still on screen when a new watch starts and the user finally answers.
        h.controller.stopTabWatch()
        h.judge.defaultVerdict = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }
        h.prompter.resolveNext(false)
        await settle()
        h.controller.pollTabs()

        XCTAssertEqual(h.log.closeScripts, [], "the new watch must not inherit the old watch's \"Close tab\" answer")
    }

    func testSubjectAndStudySitesComeFromTheLatestWatch() async {
        let page = tab("https://piazza.com/class/x", id: 5)
        let h = WatchHarness(tabs: [page])
        h.controller.startTabWatch(subject: "MATH241", studySites: ["piazza.com"])
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.judge.judgedURLs, [], "piazza.com is a study site now")

        h.controller.startTabWatch(subject: "MATH241", studySites: ["canvas.edu"])
        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.judge.judgedURLs, [page.url])
        XCTAssertEqual(h.judge.judgedSubjects, ["MATH241"])
    }

    // MARK: unsure verdicts (chat assistant)

    func testUnsureVerdictAsksTheAssistantOncePerHostAndLeavesTheTabsOpen() async {
        let a = tab("https://example.org/one", id: 5, title: "One")
        let b = tab("https://example.org/two", id: 6, title: "Two")
        let h = WatchHarness(tabs: [a, b])
        h.judge.defaultVerdict = .unsure(relevance: 0.55)
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.asker.questions, [SiteQuestion(host: "example.org", url: a.url, title: "One", relevance: 0.55)])
        XCTAssertEqual(h.asker.subjects, ["CS128"])
        XCTAssertEqual(h.prompter.asked, [], "unsure sites go to the assistant, never to the NSAlert prompt")
        XCTAssertEqual(h.judge.judgedURLs, [a.url, b.url], "no re-checks while the assistant asks")
        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testUnsureVerdictsOnDifferentHostsAreAskedSeparately() async {
        let a = tab("https://a.org/", id: 5)
        let b = tab("https://b.org/", id: 6)
        let h = WatchHarness(tabs: [a, b])
        h.judge.verdicts[a.url] = .unsure(relevance: 0.45)
        h.judge.verdicts[b.url] = .unsure(relevance: 0.65)
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.asker.questions.map(\.host), ["a.org", "b.org"])
        XCTAssertEqual(h.asker.questions.map(\.relevance), [0.45, 0.65])
    }

    func testUnsureVerdictWithoutAnAskerChangesNothing() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.controller.asker = nil
        h.judge.defaultVerdict = .unsure(relevance: 0.5)
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.prompter.asked, [])
        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.judge.judgedURLs, [page.url])
    }

    func testUnknownVerdictStillUsesThePromptAndNeverTheAssistant() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.defaultVerdict = .unknown("no key")
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.prompter.asked, ["example.org"])
        XCTAssertEqual(h.asker.questions, [])
    }

    func testUnsureVerdictThatArrivesAfterTheWatchStoppedIsIgnored() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.holds = true
        h.start()
        h.controller.pollTabs()
        await settle()

        h.controller.stopTabWatch()
        h.judge.resolveNext(.unsure(relevance: 0.5))
        await settle()

        XCTAssertEqual(h.asker.questions, [])
    }

    func testUnsureVerdictForAHostTheAssistantAlreadyDecidedIsNotAsked() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.holds = true
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        h.controller.allowHost("example.org")   // the user got an answer in the chat while the check ran
        h.judge.resolveNext(.unsure(relevance: 0.5))
        await settle()

        XCTAssertEqual(h.asker.questions, [])
    }

    func testAskedHostsStartOverWithANewWatch() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.defaultVerdict = .unsure(relevance: 0.5)
        h.start()
        h.controller.pollTabs()
        await settle()
        h.controller.stopTabWatch()

        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.asker.questions.count, 2)
    }

    // MARK: assistant decisions (SiteVerdictReceiving)

    func testDecisionsMadeWhileTheWatchIsPausedApplyWhenItRestarts() async {
        let kept = tab("https://other.org/", id: 7)
        let closed = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [kept, closed])
        h.judge.defaultVerdict = .relevant
        h.start()
        h.controller.pollTabs()
        await settle()
        h.controller.pauseTabWatch()

        var allowed: [String] = []
        h.controller.onHostAllowed = { allowed.append($0) }
        h.controller.allowHost("other.org")
        h.controller.closeHost("example.org")
        XCTAssertEqual(allowed, ["other.org"])
        XCTAssertEqual(h.log.closeScripts, [], "a paused watch cannot close a tab until it is running")

        let judged = h.judge.judgedURLs.count
        h.start()
        defer { h.controller.stopTabWatch() }
        await settle()

        XCTAssertEqual(h.judge.judgedURLs.count, judged, "a settled host is not judged again")
        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 5)])
    }

    func testAllowHostKeepsTheHostFromNowOn() async {
        let a = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [a])
        h.judge.defaultVerdict = .unsure(relevance: 0.5)
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        h.controller.allowHost("example.org")
        let b = tab("https://example.org/two", id: 6)
        h.log.tabs = [a, b]
        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.judge.judgedURLs, [a.url], "an allowed host is never judged again")
        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.asker.questions.count, 1)
    }

    func testCloseHostClosesItsOpenTabsRightAwayAndReportsEach() async {
        let study = tab("https://cs128.org/schedule", id: 1)
        let a = tab("https://example.org/one", id: 5)
        let b = tab("https://www.example.org/two", id: 6, window: 2)
        let other = tab("https://other.org/", id: 7)
        let h = WatchHarness(tabs: [study, a, b, other])
        h.judge.defaultVerdict = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }
        h.controller.pollTabs()
        await settle()

        h.controller.closeHost("example.org")

        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 5),
                                            ChromeScripts.closeTab(windowID: 2, tabID: 6)])
        XCTAssertEqual(h.closedHosts, ["example.org", "example.org"])
        XCTAssertEqual(h.log.tabs.map(\.tabID), [1, 7])
    }

    func testCloseHostAlsoClosesTheHostWhenItIsOpenedAgain() async {
        let h = WatchHarness(tabs: [])
        h.judge.defaultVerdict = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.closeHost("example.org")
        h.log.tabs = [tab("https://example.org/again", id: 9)]
        h.controller.pollTabs()

        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 9)])
        XCTAssertEqual(h.judge.judgedURLs, [], "closing, not judging")
    }

    func testCloseHostNeverTouchesStudySites() async {
        let study = tab("https://cs128.org/schedule", id: 1)
        let h = WatchHarness(tabs: [study])
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.closeHost("cs128.org")

        XCTAssertEqual(h.log.closeScripts, [])
        XCTAssertEqual(h.closedHosts, [])
    }

    func testCloseHostDoesNothingWhenNoWatchIsRunning() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])

        h.controller.closeHost("example.org")   // never started
        XCTAssertEqual(h.log.scripts, [])

        h.start()
        h.controller.stopTabWatch()
        let listedAtStart = h.log.scripts.count
        h.controller.closeHost("example.org")   // session over: a late tool call must not touch Chrome

        XCTAssertEqual(h.log.scripts.count, listedAtStart)
        XCTAssertEqual(h.closedHosts, [])
    }

    func testCloseHostDoesNothingWhileChromeIsNotRunning() async {
        let h = WatchHarness(tabs: [tab("https://example.org/one", id: 5)])
        h.log.isRunning = false
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.closeHost("example.org")

        XCTAssertEqual(h.log.scripts, [])
    }

    func testCloseHostWithAFailedListingStillClosesOnTheNextPoll() async {
        let page = tab("https://example.org/one", id: 5)
        let h = WatchHarness(tabs: [page])
        h.judge.defaultVerdict = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }
        h.log.listError = .scriptFailed("busy")

        h.controller.closeHost("example.org")
        XCTAssertEqual(h.log.closeScripts, [])

        h.log.listError = nil
        h.controller.pollTabs()
        XCTAssertEqual(h.log.closeScripts, [ChromeScripts.closeTab(windowID: 1, tabID: 5)])
    }

    // MARK: open tabs summary

    func testOpenTabsSummaryListsTheLastPolledTabsAsHostAndTitle() async {
        let study = tab("https://www.cs128.org/schedule", id: 1, title: "Schedule")
        let video = tab("https://youtube.com/watch?v=x", id: 2, title: "Lecture 4")
        let untitled = tab("https://example.org/", id: 3)
        let newTab = tab("chrome://newtab/", id: 4, title: "New Tab")
        let h = WatchHarness(tabs: [study, video, untitled, newTab])
        h.judge.defaultVerdict = .relevant
        h.start()
        defer { h.controller.stopTabWatch() }

        XCTAssertEqual(h.controller.openTabsSummary,
                       ["cs128.org — Schedule", "youtube.com — Lecture 4", "example.org", "newtab — New Tab"])
        h.controller.pollTabs()
        await settle()
        XCTAssertEqual(h.controller.openTabsSummary,
                       ["cs128.org — Schedule", "youtube.com — Lecture 4", "example.org", "newtab — New Tab"])
    }

    func testOpenTabsSummaryDropsClosedTabsAndClearsWhenTheWatchStops() async {
        let a = tab("https://example.org/one", id: 5, title: "One")
        let b = tab("https://other.org/", id: 6, title: "Other")
        let h = WatchHarness(tabs: [a, b])
        h.judge.defaultVerdict = .relevant
        h.start()
        h.controller.pollTabs()
        await settle()

        h.controller.closeHost("example.org")
        XCTAssertEqual(h.controller.openTabsSummary, ["other.org — Other"])

        h.controller.stopTabWatch()
        XCTAssertEqual(h.controller.openTabsSummary, [])
    }

    func testStartTabWatchSetsTheSubjectName() {
        let h = WatchHarness(tabs: [])
        XCTAssertEqual(h.controller.subjectName, "")
        h.controller.startTabWatch(subject: "MATH241", studySites: [])
        defer { h.controller.stopTabWatch() }
        XCTAssertEqual(h.controller.subjectName, "MATH241")
    }

    func testNothingRunsWhileChromeIsNotRunning() async {
        let h = WatchHarness(tabs: [tab("https://reddit.com/", id: 1)])
        h.log.isRunning = false
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.log.scripts, [])
        XCTAssertEqual(h.judge.judgedURLs, [])
    }

    func testFailedListingChecksNothing() async {
        let h = WatchHarness(tabs: [tab("https://reddit.com/", id: 1)])
        h.log.listError = .scriptFailed("busy")
        h.start()
        defer { h.controller.stopTabWatch() }

        h.controller.pollTabs()
        await settle()

        XCTAssertEqual(h.judge.judgedURLs, [])
        XCTAssertEqual(h.log.closeScripts, [])
    }

    func testArcWatchRemembersAnEmptySpaceSoTheNextPollDoesNotFocusIt() {
        let separator = String(ChromeScripts.fieldSeparator)
        let marker = ChromeScripts.arcEmptySpaceMarker + separator + "SPACE-1\n"
        let poker = ["W-1", "1", "T-poker", "Poker", "https://www.pokerstars.com/"].joined(separator: separator)
        var listings: [String] = []
        let controller = ChromeController(judge: FakeJudge(), prompter: FakePrompter(),
                                          alwaysBlocked: DistractionList.hosts, browser: .arc,
                                          runScript: { source in
                                              if source.contains("set sepChar") {
                                                  listings.append(source)
                                                  return .success(marker + poker + "\n")
                                              }
                                              return .success("")
                                          },
                                          chromeIsRunning: { true })
        controller.startTabWatch(subject: "MATH241", studySites: ["https://canvas.illinois.edu"])
        defer { controller.stopTabWatch() }
        controller.pollTabs()

        XCTAssertEqual(listings.count, 2, "locking in lists tabs immediately, then the timer's poll can be driven by hand")
        XCTAssertFalse(listings[0].contains("SPACE-1"))
        XCTAssertTrue(listings[1].contains("\"SPACE-1\""))
        XCTAssertEqual(controller.openTabsSummary, [], "the poker tab was closed as soon as it was listed")
    }
}
