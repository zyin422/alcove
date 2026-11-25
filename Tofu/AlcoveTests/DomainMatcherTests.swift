import XCTest
@testable import Alcove

final class DomainMatcherTests: XCTestCase {
    private let allowed = ["youtube.com", "piazza.com"]

    // MARK: normalize

    func testNormalizeLowercasesTrimsAndStripsWwwAndTrailingDots() {
        XCTAssertEqual(DomainMatcher.normalize("WWW.Piazza.com."), "piazza.com")
        XCTAssertEqual(DomainMatcher.normalize("  YouTube.com \n"), "youtube.com")
        XCTAssertEqual(DomainMatcher.normalize("example.org.."), "example.org")
        XCTAssertEqual(DomainMatcher.normalize("docs.python.org"), "docs.python.org")
        XCTAssertEqual(DomainMatcher.normalize("wwwexample.com"), "wwwexample.com")
        XCTAssertEqual(DomainMatcher.normalize(""), "")
    }

    // MARK: normalizedURL

    func testNormalizedURLAddsHTTPSWhenTheSchemeIsMissing() {
        XCTAssertEqual(DomainMatcher.normalizedURL("piazza.com/class/x")?.absoluteString,
                       "https://piazza.com/class/x")
        XCTAssertEqual(DomainMatcher.normalizedURL("Piazza.com/class/x")?.scheme, "https")
        XCTAssertEqual(DomainMatcher.normalizedURL("localhost:3000")?.absoluteString, "https://localhost:3000")
        XCTAssertEqual(DomainMatcher.normalizedURL("piazza.com/r?next=https://x.com")?.host(percentEncoded: false),
                       "piazza.com")
    }

    func testNormalizedURLKeepsAnExistingSchemeAndTrims() {
        XCTAssertEqual(DomainMatcher.normalizedURL("http://example.com/a")?.absoluteString, "http://example.com/a")
        XCTAssertEqual(DomainMatcher.normalizedURL("  https://cs128.org/  ")?.absoluteString, "https://cs128.org/")
    }

    func testNormalizedURLIsNilForBlankOrHostlessInput() {
        XCTAssertNil(DomainMatcher.normalizedURL("  "))
        XCTAssertNil(DomainMatcher.normalizedURL(""))
        XCTAssertNil(DomainMatcher.normalizedURL("https://"))
        XCTAssertNil(DomainMatcher.normalizedURL("not a url"))
        XCTAssertNil(DomainMatcher.normalizedURL("%%%"))
    }

    // MARK: host(of:)

    func testHostOfNormalizesAndAcceptsMissingScheme() {
        XCTAssertEqual(DomainMatcher.host(of: "https://www.YouTube.com/watch?v=x"), "youtube.com")
        XCTAssertEqual(DomainMatcher.host(of: "piazza.com/class/x"), "piazza.com")
        XCTAssertEqual(DomainMatcher.host(of: "Piazza.com/class/x"), "piazza.com")
        XCTAssertEqual(DomainMatcher.host(of: "http://localhost:3000/app"), "localhost")
        XCTAssertEqual(DomainMatcher.host(of: "https://m.youtube.com./feed"), "m.youtube.com")
        XCTAssertNil(DomainMatcher.host(of: ""))
        XCTAssertNil(DomainMatcher.host(of: "   "))
        XCTAssertNil(DomainMatcher.host(of: "https://"))
    }

    // MARK: allowedDomains

    func testAllowedDomainsMergesSitesAndExtrasNormalizedAndDeduplicated() {
        let domains = DomainMatcher.allowedDomains(
            sites: ["https://www.YouTube.com/watch?v=x", "Piazza.com/class/x"],
            extra: ["WWW.StackOverflow.com.", "piazza.com", "youtube.com", "", "   ", "docs.python.org/3/"])
        XCTAssertEqual(domains, ["youtube.com", "piazza.com", "stackoverflow.com", "docs.python.org"])
    }

    func testAllowedDomainsOfNothingIsEmpty() {
        XCTAssertEqual(DomainMatcher.allowedDomains(sites: [], extra: []), [])
        XCTAssertEqual(DomainMatcher.allowedDomains(sites: [""], extra: ["  "]), [])
    }

    // MARK: isAllowed

    func testExactHostIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://youtube.com/watch?v=1", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com/class/x", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://www.piazza.com/", allowed: allowed))
    }

    func testSubdomainIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://m.youtube.com/feed", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://a.b.piazza.com/", allowed: allowed))
    }

    func testLookalikeHostsAreNotAllowed() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://notyoutube.com/", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com.evil.com/", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com@evil.com/", allowed: allowed))
    }

    func testDifferentDomainIsNotAllowed() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://www.reddit.com/r/all", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("http://twitter.com", allowed: allowed))
    }

    func testBlankTabsAndChromeInternalPagesAreAllowed() {
        let internalPages = [
            "chrome://newtab", "chrome://newtab/", "chrome://new-tab-page/", "chrome://settings",
            "chrome://settings/privacy", "Chrome://Settings", "about:blank", "arc://newtab", "arc://newtab/", "", "   ",
            "chrome-extension://abcdefghijklmnop/popup.html", "chrome-search://local-ntp/local-ntp.html",
        ]
        for url in internalPages {
            XCTAssertTrue(DomainMatcher.isAllowed(url, allowed: allowed), "\(url.debugDescription) should be allowed")
        }
    }

    func testUnparseableURLsAreAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("%%%", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("not a url", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://", allowed: allowed))
    }

    func testUppercaseHostIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("HTTPS://WWW.YOUTUBE.COM/WATCH?V=1", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://M.YouTube.COM/", allowed: allowed))
    }

    func testPortIsIgnored() {
        XCTAssertTrue(DomainMatcher.isAllowed("http://localhost:3000/app", allowed: ["localhost"]))
        XCTAssertFalse(DomainMatcher.isAllowed("http://localhost:3000/app", allowed: ["piazza.com"]))
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com:8443/x", allowed: allowed))
    }

    func testAllowedEntriesAreNormalizedBeforeMatching() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://youtube.com/", allowed: ["WWW.YouTube.com."]))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: ["", "  "]))
    }

    func testEmptyAllowListClosesWebPagesButKeepsBlankTabs() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: []))
        XCTAssertTrue(DomainMatcher.isAllowed("chrome://newtab/", allowed: []))
    }

    /// Review Focus 2: a site typed without a scheme, with uppercase letters.
    func testSiteTypedWithoutSchemeOpensAsHTTPSAndAllowsItsDomain() {
        XCTAssertEqual(DomainMatcher.normalizedURL("Piazza.com/class/x")?.absoluteString, "https://Piazza.com/class/x")
        let domains = DomainMatcher.allowedDomains(sites: ["Piazza.com/class/x"], extra: [])
        XCTAssertEqual(domains, ["piazza.com"])
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com/class/x/post/42", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("https://www.piazza.com/", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("https://cdn.piazza.com/file.pdf", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("chrome://newtab/", allowed: domains))
        XCTAssertFalse(DomainMatcher.isAllowed("https://notpiazza.com/", allowed: domains))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: domains))
    }

    // MARK: isSearchEngine

    func testIsSearchEngineRecognizesGoogleAndOtherMajorSearchEngines() {
        let searchURLs = [
            "https://www.google.com",
            "https://google.com",
            "https://www.google.com/search?q=swift+concurrency",
            "https://google.com/search?q=apple+developer",
            "https://www.google.co.uk/search?q=test",
            "https://google.ca",
            "https://duckduckgo.com/?q=test",
            "https://www.bing.com/search?q=test",
            "https://kagi.com",
            "https://ecosia.org",
            "https://search.brave.com",
            "google.com",
            "www.google.com",
        ]
        for url in searchURLs {
            XCTAssertTrue(DomainMatcher.isSearchEngine(url), "\(url) must be recognized as search engine")
        }

        let nonSearchURLs = [
            "https://reddit.com/r/all",
            "https://notgoogle.com",
            "https://google.com.evil.com",
            "https://youtube.com",
            "https://piazza.com",
            "",
            "   ",
        ]
        for url in nonSearchURLs {
            XCTAssertFalse(DomainMatcher.isSearchEngine(url), "\(url) must NOT be recognized as search engine")
        }
    }

    // MARK: - AllowedAppDomains

    func testAllowedAppDomainsKnownApps() {
        let spotify = AllowedApp(bundleID: "com.spotify.client", name: "Spotify")
        let spotifyDomains = AllowedAppDomains.domains(for: spotify)
        XCTAssertTrue(spotifyDomains.contains("spotify.com"))
        XCTAssertTrue(spotifyDomains.contains("scdn.co"))

        let wechat = AllowedApp(bundleID: "com.tencent.xinwechat", name: "WeChat")
        let wechatDomains = AllowedAppDomains.domains(for: wechat)
        XCTAssertTrue(wechatDomains.contains("wechat.com"))
        XCTAssertTrue(wechatDomains.contains("weixin.qq.com"))

        let slack = AllowedApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        let slackDomains = AllowedAppDomains.domains(for: slack)
        XCTAssertTrue(slackDomains.contains("slack.com"))
    }

    func testAllowedAppDomainsReverseDomainFallback() {
        let app = AllowedApp(bundleID: "com.example.desktop", name: "Example")
        let domains = AllowedAppDomains.domains(for: app)
        XCTAssertEqual(domains, ["example.com"])
    }

    func testAllowedAppDomainsUnknownAppWithoutStandardPrefix() {
        let app = AllowedApp(bundleID: "mycustomapp", name: "Custom")
        let domains = AllowedAppDomains.domains(for: app)
        XCTAssertTrue(domains.isEmpty)
    }
}
