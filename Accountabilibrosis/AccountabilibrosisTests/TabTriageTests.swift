import XCTest
@testable import Accountabilibrosis

final class TabTriageTests: XCTestCase {
    private func tab(_ url: String, window: Int = 1, index: Int = 1, id: Int = 1, title: String = "") -> ChromeTab {
        ChromeTab(windowID: window, tabIndex: index, tabID: id, title: title, url: url)
    }

    private func makeTriage(sites: [String] = ["https://cs128.org/schedule"], protected: Set<String> = []) -> TabTriage {
        TabTriage(studySites: sites, protected: protected)
    }

    // MARK: tabsToCheck

    func testNewOffSiteTabNeedsAVerdict() {
        var triage = makeTriage()
        let reddit = tab("https://reddit.com/r/all", id: 5)
        XCTAssertEqual(triage.tabsToCheck([reddit]), [reddit])
    }

    func testChromeInternalBlankAndUnparseableTabsAreSkipped() {
        var triage = makeTriage()
        let tabs = [tab("chrome://newtab/", id: 1), tab("about:blank", id: 2), tab("", id: 3),
                    tab("chrome-extension://abc/page.html", id: 4), tab("not a url", id: 5)]
        XCTAssertEqual(triage.tabsToCheck(tabs), [])
    }

    func testStudySiteHostsAndSubdomainsAreSkipped() {
        var triage = makeTriage(sites: ["https://cs128.org/schedule", "piazza.com"])
        let tabs = [tab("https://cs128.org/other", id: 1), tab("https://www.cs128.org/x", id: 2),
                    tab("https://campuswire.cs128.org/", id: 3), tab("https://piazza.com/class/x", id: 4)]
        XCTAssertEqual(triage.tabsToCheck(tabs), [])
    }

    func testLookalikeHostOfAStudySiteIsStillChecked() {
        var triage = makeTriage()
        let fake = tab("https://notcs128.org/", id: 1)
        XCTAssertEqual(triage.tabsToCheck([fake]), [fake])
    }

    func testProtectedPreexistingTabIsSkippedButSameURLInAnotherWindowIsNot() {
        let old = tab("https://youtube.com/watch?v=old", window: 9, id: 1)
        var triage = makeTriage(protected: [ChromeScripts.protectionKey(old)])
        let fresh = tab("https://youtube.com/watch?v=old", window: 50, id: 2)
        XCTAssertEqual(triage.tabsToCheck([old, fresh]), [fresh])
    }

    func testURLInFlightIsNotCheckedAgain() {
        var triage = makeTriage()
        let reddit = tab("https://reddit.com/r/all", id: 5)
        XCTAssertEqual(triage.tabsToCheck([reddit]), [reddit])
        XCTAssertEqual(triage.tabsToCheck([reddit]), [])
    }

    func testTwoTabsWithTheSameURLInOnePollAreCheckedOnce() {
        var triage = makeTriage()
        let a = tab("https://reddit.com/r/all", index: 1, id: 5)
        let b = tab("https://reddit.com/r/all", index: 2, id: 6)
        XCTAssertEqual(triage.tabsToCheck([a, b]), [a])
    }

    func testDifferentURLOnTheSameHostIsCheckedSeparately() {
        var triage = makeTriage()
        let a = tab("https://youtube.com/watch?v=1", id: 1)
        let b = tab("https://youtube.com/watch?v=2", id: 2)
        XCTAssertEqual(triage.tabsToCheck([a, b]), [a, b])
    }

    // MARK: record

    func testRelevantURLIsKeptAndNeverCheckedOrClosedAgain() {
        var triage = makeTriage()
        let video = tab("https://youtube.com/watch?v=lecture", id: 5)
        _ = triage.tabsToCheck([video])
        triage.record(url: video.url, verdict: .relevant)

        XCTAssertEqual(triage.tabsToCheck([video]), [])
        XCTAssertFalse(triage.shouldCloseImmediately(video))
    }

    func testOffTaskURLIsClosedImmediatelyWhenItReappears() {
        var triage = makeTriage()
        let reddit = tab("https://reddit.com/r/all", id: 5)
        _ = triage.tabsToCheck([reddit])
        triage.record(url: reddit.url, verdict: .offTask)

        let again = tab("https://reddit.com/r/all", window: 2, index: 3, id: 99)
        XCTAssertTrue(triage.shouldCloseImmediately(again))
        XCTAssertEqual(triage.tabsToCheck([again]), [], "a decided URL needs no new verdict")
    }

    func testOffTaskVerdictDoesNotCloseOtherURLsOnTheSameHost() {
        var triage = makeTriage()
        let reddit = tab("https://reddit.com/r/all", id: 5)
        _ = triage.tabsToCheck([reddit])
        triage.record(url: reddit.url, verdict: .offTask)

        let other = tab("https://reddit.com/r/cs128", id: 6)
        XCTAssertFalse(triage.shouldCloseImmediately(other))
        XCTAssertEqual(triage.tabsToCheck([other]), [other])
    }

    func testUnknownVerdictClearsInFlightAndWaitsForTheUserInsteadOfRechecking() {
        var triage = makeTriage()
        let blog = tab("https://example.org/post", id: 5)
        _ = triage.tabsToCheck([blog])
        triage.record(url: blog.url, verdict: .unknown("offline"))

        XCTAssertFalse(triage.shouldCloseImmediately(blog), "no verdict yet: the tab stays until the user answers")
        XCTAssertEqual(triage.tabsToCheck([blog]), [], "awaiting the prompt, not re-judged every 2 s")
    }

    func testStudySiteAndInternalTabsAreNeverClosedImmediately() {
        var triage = makeTriage()
        triage.record(url: "https://cs128.org/schedule", verdict: .offTask)
        triage.recordAnswer(host: "cs128.org", needed: false)
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://cs128.org/schedule")))
        XCTAssertFalse(triage.shouldCloseImmediately(tab("chrome://newtab/")))
    }

    func testProtectedTabIsNeverClosedImmediately() {
        let old = tab("https://reddit.com/r/all", window: 9, id: 1)
        var triage = makeTriage(protected: [ChromeScripts.protectionKey(old)])
        triage.record(url: old.url, verdict: .offTask)
        triage.recordAnswer(host: "reddit.com", needed: false)
        XCTAssertFalse(triage.shouldCloseImmediately(old))
    }

    // MARK: unsure (waiting for the chat assistant)

    func testUnsureVerdictWaitsForTheAssistantInsteadOfRecheckingOrClosing() {
        var triage = makeTriage()
        let page = tab("https://piazza.com/class/x", id: 5)
        _ = triage.tabsToCheck([page])
        triage.record(url: page.url, verdict: .unsure(relevance: 0.55))

        XCTAssertFalse(triage.shouldCloseImmediately(page), "the tab stays open while the assistant asks")
        XCTAssertEqual(triage.tabsToCheck([page]), [], "awaiting the assistant, not re-judged every 2 s")
    }

    func testUnsureVerdictOnlyHoldsItsOwnURL() {
        var triage = makeTriage()
        let page = tab("https://piazza.com/class/x", id: 5)
        let other = tab("https://piazza.com/class/y", id: 6)
        _ = triage.tabsToCheck([page])
        triage.record(url: page.url, verdict: .unsure(relevance: 0.5))

        XCTAssertEqual(triage.tabsToCheck([other]), [other])
    }

    func testAllowHostKeepsTheWholeHostAfterAnUnsureVerdict() {
        var triage = makeTriage()
        let first = tab("https://example.org/one", id: 1)
        _ = triage.tabsToCheck([first])
        triage.record(url: first.url, verdict: .unsure(relevance: 0.5))
        triage.allowHost("example.org")

        let later = tab("https://example.org/two", id: 2)
        XCTAssertEqual(triage.tabsToCheck([first, later]), [])
        XCTAssertFalse(triage.shouldCloseImmediately(first))
        XCTAssertFalse(triage.shouldCloseImmediately(later))
    }

    func testCloseHostClosesEveryTabOfTheHostAfterAnUnsureVerdict() {
        var triage = makeTriage()
        let first = tab("https://example.org/one", id: 1)
        _ = triage.tabsToCheck([first])
        triage.record(url: first.url, verdict: .unsure(relevance: 0.5))
        triage.closeHost("example.org")

        let later = tab("https://example.org/two", id: 2)
        XCTAssertTrue(triage.shouldCloseImmediately(first))
        XCTAssertTrue(triage.shouldCloseImmediately(later))
        XCTAssertEqual(triage.tabsToCheck([first, later]), [], "closing, not judging")
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://different.org/")))
    }

    func testAllowAndCloseHostNormalizeTheHostLikeTabHosts() {
        var triage = makeTriage()
        triage.closeHost("WWW.Example.org")
        XCTAssertTrue(triage.shouldCloseImmediately(tab("https://example.org/a")))
        XCTAssertTrue(triage.shouldCloseImmediately(tab("https://www.example.org/b")))

        triage.allowHost("www.EXAMPLE.org")
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://example.org/a")))
    }

    func testLaterAssistantDecisionForTheSameHostReplacesTheEarlierOne() {
        var triage = makeTriage()
        let page = tab("https://example.org/a")
        triage.allowHost("example.org")
        triage.closeHost("example.org")
        XCTAssertTrue(triage.shouldCloseImmediately(page))

        triage.allowHost("example.org")
        XCTAssertFalse(triage.shouldCloseImmediately(page))
        XCTAssertEqual(triage.tabsToCheck([page]), [])
    }

    func testAllowHostBeatsAnEarlierOffTaskVerdictForAURL() {
        var triage = makeTriage()
        let page = tab("https://example.org/a", id: 1)
        _ = triage.tabsToCheck([page])
        triage.record(url: page.url, verdict: .offTask)
        triage.allowHost("example.org")
        XCTAssertFalse(triage.shouldCloseImmediately(page))
    }

    func testCloseHostNeverClosesStudySitesProtectedTabsOrChromePages() {
        let old = tab("https://reddit.com/r/all", window: 9, id: 1)
        var triage = makeTriage(protected: [ChromeScripts.protectionKey(old)])
        triage.closeHost("cs128.org")
        triage.closeHost("reddit.com")
        triage.closeHost("newtab")

        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://cs128.org/schedule")))
        XCTAssertFalse(triage.shouldCloseImmediately(old))
        XCTAssertFalse(triage.shouldCloseImmediately(tab("chrome://newtab/")))
        XCTAssertTrue(triage.shouldCloseImmediately(tab("https://reddit.com/r/all", window: 50, id: 2)))
    }

    func testIsHostAnsweredReflectsAllowAndCloseDecisions() {
        var triage = makeTriage()
        let page = tab("https://example.org/a")
        XCTAssertFalse(triage.isHostAnswered(page))
        triage.allowHost("example.org")
        XCTAssertTrue(triage.isHostAnswered(page))

        var other = makeTriage()
        other.closeHost("example.org")
        XCTAssertTrue(other.isHostAnswered(page))
        XCTAssertFalse(other.isHostAnswered(tab("https://different.org/")))
    }

    // MARK: recordAnswer

    func testNeededAnswerKeepsTheWholeHostForTheSession() {
        var triage = makeTriage()
        let first = tab("https://stackoverflow.com/q/1", id: 1)
        _ = triage.tabsToCheck([first])
        triage.record(url: first.url, verdict: .unknown("no key"))
        triage.recordAnswer(host: "stackoverflow.com", needed: true)

        let later = tab("https://stackoverflow.com/q/2", id: 2)
        XCTAssertEqual(triage.tabsToCheck([first, later]), [])
        XCTAssertFalse(triage.shouldCloseImmediately(later))
    }

    func testNotNeededAnswerClosesEveryTabOfTheHostForTheSession() {
        var triage = makeTriage()
        let first = tab("https://example.org/post", id: 1)
        _ = triage.tabsToCheck([first])
        triage.record(url: first.url, verdict: .unknown("no key"))
        triage.recordAnswer(host: "example.org", needed: false)

        let other = tab("https://example.org/another", id: 2)
        XCTAssertTrue(triage.shouldCloseImmediately(first))
        XCTAssertTrue(triage.shouldCloseImmediately(other))
        XCTAssertEqual(triage.tabsToCheck([first, other]), [], "closing, not judging")
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://different.org/")))
    }

    func testAnswerHostIsNormalizedLikeTabHosts() {
        var triage = makeTriage()
        triage.recordAnswer(host: "WWW.Example.org", needed: false)
        XCTAssertTrue(triage.shouldCloseImmediately(tab("https://example.org/a")))
        XCTAssertTrue(triage.shouldCloseImmediately(tab("https://www.example.org/b")))
    }

    func testLaterAnswerForTheSameHostReplacesTheEarlierOne() {
        var triage = makeTriage()
        triage.recordAnswer(host: "example.org", needed: false)
        triage.recordAnswer(host: "example.org", needed: true)
        let page = tab("https://example.org/a")
        XCTAssertFalse(triage.shouldCloseImmediately(page))
        XCTAssertEqual(triage.tabsToCheck([page]), [])

        triage.recordAnswer(host: "example.org", needed: false)
        XCTAssertTrue(triage.shouldCloseImmediately(page))
    }

    func testNeededHostWinsOverAnEarlierOffTaskVerdictForAURL() {
        var triage = makeTriage()
        let page = tab("https://example.org/a", id: 1)
        _ = triage.tabsToCheck([page])
        triage.record(url: page.url, verdict: .offTask)
        triage.recordAnswer(host: "example.org", needed: true)
        XCTAssertFalse(triage.shouldCloseImmediately(page))
    }
}
