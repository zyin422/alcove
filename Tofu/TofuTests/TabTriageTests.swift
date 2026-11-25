import XCTest
@testable import Tofu

final class TabTriageTests: XCTestCase {
    private func tab(_ url: String, window: Int = 1, index: Int = 1, id: Int = 1, title: String = "") -> ChromeTab {
        ChromeTab(windowID: ScriptID(window), tabIndex: index, tabID: ScriptID(id), title: title, url: url)
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

    func testRelatedTabsAreStudySitesAndHostsAllowedDuringTheBlock() {
        var triage = makeTriage(sites: ["https://cs128.org"])
        XCTAssertTrue(triage.isRelated(tab("https://cs128.org/schedule")))
        XCTAssertFalse(triage.isRelated(tab("https://reddit.com")))
        triage.allowHost("reddit.com")
        XCTAssertTrue(triage.isRelated(tab("https://www.reddit.com/r/swift")))
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

    // MARK: Always-blocked sites

    private func blockingTriage(sites: [String] = ["https://cs128.org/schedule"], protected: Set<String> = []) -> TabTriage {
        TabTriage(studySites: sites, protected: protected, alwaysBlocked: DistractionList.hosts)
    }

    func testGmailAndOtherDistractionsCloseWithoutAVerdict() {
        var triage = blockingTriage()
        let tabs = [tab("https://mail.google.com/mail/u/0/#inbox", id: 1), tab("https://www.instagram.com/", id: 2),
                    tab("https://m.youtube.com/watch?v=1", id: 3), tab("https://www.amazon.com/dp/x", id: 4),
                    tab("https://www.netflix.com/browse", id: 5)]
        XCTAssertEqual(triage.tabsToCheck(tabs), [])
        for page in tabs {
            XCTAssertTrue(triage.shouldCloseImmediately(page), page.url)
        }
    }

    func testPreexistingBlockedTabIsClosedButOtherPreexistingTabsAreLeftAlone() {
        let gmail = tab("https://mail.google.com/mail/u/0/", id: 1)
        let docs = tab("https://example.org/notes", id: 2)
        let triage = blockingTriage(protected: [ChromeScripts.protectionKey(gmail), ChromeScripts.protectionKey(docs)])
        XCTAssertTrue(triage.shouldCloseImmediately(gmail))
        XCTAssertFalse(triage.shouldCloseImmediately(docs))
    }

    func testStudySiteOnABlockedDomainIsKept() {
        var triage = blockingTriage(sites: ["https://www.youtube.com/@cs128"])
        let lecture = tab("https://www.youtube.com/watch?v=lecture", id: 1)
        XCTAssertFalse(triage.shouldCloseImmediately(lecture))
        XCTAssertEqual(triage.tabsToCheck([lecture]), [])
    }

    func testHostTheUserSaidIsNeededBeatsTheBlockList() {
        var triage = blockingTriage()
        triage.allowHost("youtube.com")
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://www.youtube.com/watch?v=1")))
    }

    func testExceptionsAndLookalikesAreJudgedNormally() {
        var triage = blockingTriage()
        let aws = tab("https://aws.amazon.com/s3/", id: 1)
        let lookalike = tab("https://notyoutube.com/", id: 2)
        let google = tab("https://docs.google.com/document/d/1", id: 3)
        XCTAssertFalse(triage.shouldCloseImmediately(aws))
        XCTAssertFalse(triage.shouldCloseImmediately(lookalike))
        XCTAssertFalse(triage.shouldCloseImmediately(google))
        XCTAssertEqual(triage.tabsToCheck([aws, lookalike, google]), [aws, lookalike, google])
    }

    func testWithoutABlockListNothingIsClosedUpFront() {
        let triage = makeTriage()
        XCTAssertFalse(triage.shouldCloseImmediately(tab("https://mail.google.com/", id: 1)))
    }

    func testNonVideoDistractionCannotBeMarkedAsNeeded() {
        var triage = blockingTriage()
        triage.allowHost("discord.com")
        triage.allowHost("reddit.com")
        let discordTab = tab("https://discord.com/channels/123", id: 10)
        let redditTab = tab("https://reddit.com/r/all", id: 11)
        XCTAssertTrue(triage.shouldCloseImmediately(discordTab))
        XCTAssertTrue(triage.shouldCloseImmediately(redditTab))
        XCTAssertFalse(triage.isRelated(discordTab))
        XCTAssertFalse(triage.isRelated(redditTab))
    }

    func testSearchEngineHomepagesAreKeptWhileSearchQueriesAreJudged() {
        var triage = blockingTriage()
        let googleHome = tab("https://www.google.com", id: 1)
        let duckduckgoHome = tab("https://duckduckgo.com/", id: 2)
        let bingHome = tab("https://www.bing.com/", id: 3)
        let offTaskSearch = tab("https://www.google.com/search?q=minecraft+ai+videos", id: 4)
        let workSearch = tab("https://www.google.com/search?q=swift+concurrency", id: 5)

        // Bare homepages stay unchecked so users can type a query; active search URLs MUST go to the AI judge.
        XCTAssertEqual(triage.tabsToCheck([googleHome, duckduckgoHome, bingHome, offTaskSearch, workSearch]),
                       [offTaskSearch, workSearch])
        XCTAssertFalse(triage.shouldCloseImmediately(googleHome))
        XCTAssertTrue(triage.isRelated(googleHome))
        XCTAssertFalse(triage.isRelated(offTaskSearch), "unjudged search query should not survive break recovery automatically")

        // Judging the queries sets per-URL status accurately.
        triage.record(url: offTaskSearch.url, verdict: .offTask)
        triage.record(url: workSearch.url, verdict: .relevant)
        XCTAssertTrue(triage.shouldCloseImmediately(offTaskSearch))
        XCTAssertFalse(triage.shouldCloseImmediately(workSearch))
        XCTAssertTrue(triage.isRelated(workSearch))
    }

    func testGoogleVideoPreviewAndVideoSearchTabsAreAlwaysBlocked() {
        var triage = blockingTriage()
        let previewModal = tab("https://www.google.com/search?q=minecraft+ai+videos#fpstate=ive&vld=cid:a,vid:b", id: 1)
        let videoTabUDM7 = tab("https://www.google.com/search?q=minecraft+ai+videos&udm=7", id: 2)
        let videoTabTBM = tab("https://www.google.com/search?q=minecraft+ai+videos&tbm=vid", id: 3)
        let shortVideos = tab("https://www.google.com/search?q=minecraft&udm=39", id: 4)
        let ytEmbed = tab("https://www.youtube-nocookie.com/embed/abc", id: 5)
        let bingVideos = tab("https://www.bing.com/videos/search?q=minecraft", id: 6)

        for page in [previewModal, videoTabUDM7, videoTabTBM, shortVideos, ytEmbed, bingVideos] {
            XCTAssertTrue(triage.shouldCloseImmediately(page), page.url)
            XCTAssertFalse(triage.isRelated(page), page.url)
        }
        XCTAssertEqual(triage.tabsToCheck([previewModal, videoTabUDM7, videoTabTBM, shortVideos, ytEmbed, bingVideos]), [])
    }

    func testAllowOrCloseHostNeverBlanketWhitelistsOrBansSearchEngines() {
        var triage = blockingTriage()
        triage.allowHost("google.com")
        let distractedSearch = tab("https://www.google.com/search?q=minecraft+ai+videos", id: 1)
        XCTAssertEqual(triage.tabsToCheck([distractedSearch]), [distractedSearch],
                       "allowing google.com must never whitelist future unrelated search queries")

        triage.closeHost("google.com")
        let workSearch = tab("https://www.google.com/search?q=cs128+pointers", id: 2)
        XCTAssertFalse(triage.shouldCloseImmediately(workSearch),
                       "closing google.com must not ban unrelated work searches; use keepURL/closeURL per URL")

        triage.closeURL(distractedSearch.url)
        triage.keepURL(workSearch.url)
        XCTAssertTrue(triage.shouldCloseImmediately(distractedSearch))
        XCTAssertFalse(triage.shouldCloseImmediately(workSearch))
    }

    func testDistractionsUnderGoogleDomainRemainBlocked() {
        let triage = blockingTriage()
        let gmail = tab("https://mail.google.com/mail/u/0/", id: 1)
        let gchat = tab("https://chat.google.com/", id: 2)

        XCTAssertTrue(triage.shouldCloseImmediately(gmail))
        XCTAssertTrue(triage.shouldCloseImmediately(gchat))
    }
}
