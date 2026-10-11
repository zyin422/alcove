import XCTest
@testable import Accountabilibrosis

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
                    [String($0.windowID), String($0.tabIndex), String($0.tabID), $0.title, $0.url]
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
        let log = ScriptLog()
        let controller: ChromeController
        private(set) var closedHosts: [String] = []

        init(tabs: [ChromeTab]) {
            log.tabs = tabs
            let log = self.log
            controller = ChromeController(judge: judge, prompter: prompter,
                                          runScript: { log.run($0) }, chromeIsRunning: { log.isRunning })
            controller.onTabClosed = { [unowned self] host in self.closedHosts.append(host) }
        }

        func start() {
            controller.startTabWatch(subject: "CS128", studySites: ["https://cs128.org/schedule"])
        }
    }

    private func tab(_ url: String, id: Int, window: Int = 1, title: String = "") -> ChromeTab {
        ChromeTab(windowID: window, tabIndex: id, tabID: id, title: title, url: url)
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
}
