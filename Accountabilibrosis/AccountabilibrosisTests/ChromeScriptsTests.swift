import XCTest
@testable import Accountabilibrosis

final class ChromeScriptsTests: XCTestCase {
    // MARK: escape

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(ChromeScripts.escape(#"a"b\c"#), #"a\"b\\c"#)
        XCTAssertEqual(ChromeScripts.escape("https://example.com/?q=1"), "https://example.com/?q=1")
    }

    // MARK: openWindow

    func testOpenWindowMakesWindowSetsEscapedURLAndBounds() {
        let script = ChromeScripts.openWindow(url: #"https://example.com/a"b"#,
                                              bounds: ChromeBounds(left: 0, top: 30, right: 840, bottom: 1050))
        XCTAssertTrue(script.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(script.contains("make new window"))
        XCTAssertTrue(script.contains(#"set URL of active tab of w to "https://example.com/a\"b""#))
        XCTAssertTrue(script.contains("set bounds of w to {0, 30, 840, 1050}"))
        XCTAssertTrue(script.contains("return id of w as text"))
    }

    func testOpenWindowWithoutBoundsHasNoBoundsLine() {
        let script = ChromeScripts.openWindow(url: "https://piazza.com/class/x")
        XCTAssertTrue(script.contains("make new window"))
        XCTAssertTrue(script.contains(#"set URL of active tab of w to "https://piazza.com/class/x""#))
        XCTAssertFalse(script.contains("bounds"))
        XCTAssertTrue(script.contains("return id of w as text"))
    }

    // MARK: other scripts

    func testCloseTabTargetsTabIndexOfWindowID() {
        XCTAssertEqual(ChromeScripts.closeTab(windowID: 12, tabIndex: 3),
                       #"tell application "Google Chrome" to close tab 3 of window id "12""#)
    }

    func testRestoreUnminimizesEachIDInsideTry() {
        let script = ChromeScripts.restore(windowIDs: [5, 9])
        XCTAssertTrue(script.contains(#"set minimized of window id "5" to false"#))
        XCTAssertTrue(script.contains(#"set minimized of window id "9" to false"#))
        XCTAssertEqual(script.components(separatedBy: "try").count - 1, 4)   // 2 × "try" + 2 × "end try"
    }

    func testListTabsUsesTabAndLinefeedCapturedOutsideTell() {
        let script = ChromeScripts.listTabs
        XCTAssertTrue(script.hasPrefix("set tabChar to tab\nset lineChar to linefeed"))
        XCTAssertTrue(script.contains("URL of every tab of w"))
    }

    func testMinimizeAllAndPingTargetChrome() {
        XCTAssertTrue(ChromeScripts.minimizeAll.contains("set minimized of w to true"))
        XCTAssertTrue(ChromeScripts.minimizeAll.contains(#"set AppleScript's text item delimiters to ",""#))
        XCTAssertEqual(ChromeScripts.ping, #"tell application "Google Chrome" to count windows"#)
    }

    // MARK: parseTabs

    func testParseTabsMultipleLinesWithTrailingNewline() {
        let output = "101\t1\thttps://piazza.com/class/x\n101\t2\thttps://www.youtube.com/watch?v=1\n202\t1\tchrome://newtab/\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 101, tabIndex: 1, url: "https://piazza.com/class/x"),
            ChromeTab(windowID: 101, tabIndex: 2, url: "https://www.youtube.com/watch?v=1"),
            ChromeTab(windowID: 202, tabIndex: 1, url: "chrome://newtab/"),
        ])
    }

    func testParseTabsSkipsMalformedLines() {
        let output = "garbage\n1\t2\nx\t1\thttps://a.com\n1\ty\thttps://b.com\n\n7\t3\thttps://ok.com\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [ChromeTab(windowID: 7, tabIndex: 3, url: "https://ok.com")])
    }

    func testParseTabsKeepsURLWithSpacesAndHandlesCRLF() {
        let output = "3\t1\tfile:///Users/me/My Notes.pdf\r\n3\t2\thttps://a.com"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 3, tabIndex: 1, url: "file:///Users/me/My Notes.pdf"),
            ChromeTab(windowID: 3, tabIndex: 2, url: "https://a.com"),
        ])
    }

    func testParseTabsEmptyOutput() {
        XCTAssertEqual(ChromeScripts.parseTabs(""), [])
    }

    // MARK: parseIDs

    func testParseIDs() {
        XCTAssertEqual(ChromeScripts.parseIDs(""), [])
        XCTAssertEqual(ChromeScripts.parseIDs("1,2, 3"), [1, 2, 3])
        XCTAssertEqual(ChromeScripts.parseIDs("junk"), [])
        XCTAssertEqual(ChromeScripts.parseIDs("4,junk,5\n"), [4, 5])
        XCTAssertEqual(ChromeScripts.parseIDs("1234567890"), [1_234_567_890])
    }

    // MARK: tabsToClose

    func testTabsToCloseKeepsAllowedAndBlankTabsAndOrdersDescendingPerWindow() {
        let tabs = [
            ChromeTab(windowID: 1, tabIndex: 1, url: "https://piazza.com/class/x"),
            ChromeTab(windowID: 1, tabIndex: 2, url: "https://reddit.com/r/all"),
            ChromeTab(windowID: 1, tabIndex: 3, url: "chrome://newtab/"),
            ChromeTab(windowID: 1, tabIndex: 4, url: "https://notyoutube.com/"),
            ChromeTab(windowID: 1, tabIndex: 5, url: "https://m.youtube.com/watch?v=1"),
            ChromeTab(windowID: 2, tabIndex: 1, url: "https://x.com/home"),
            ChromeTab(windowID: 2, tabIndex: 2, url: "about:blank"),
        ]
        let result = ChromeScripts.tabsToClose(tabs, allowedDomains: ["piazza.com", "youtube.com"])
        XCTAssertEqual(result, [
            ChromeTab(windowID: 1, tabIndex: 4, url: "https://notyoutube.com/"),
            ChromeTab(windowID: 1, tabIndex: 2, url: "https://reddit.com/r/all"),
            ChromeTab(windowID: 2, tabIndex: 1, url: "https://x.com/home"),
        ])
    }

    func testTabsToCloseIsEmptyWhenEverythingAllowed() {
        let tabs = [ChromeTab(windowID: 1, tabIndex: 1, url: "https://www.Piazza.com/class/x")]
        XCTAssertEqual(ChromeScripts.tabsToClose(tabs, allowedDomains: ["piazza.com"]), [])
    }

    func testProtectionKeyIsWindowAndURL() {
        XCTAssertEqual(ChromeScripts.protectionKey(ChromeTab(windowID: 9, tabIndex: 4, url: "https://a.com")),
                       "9\thttps://a.com")
    }

    func testPreexistingTabsAreProtectedButNewTabsInTheSameWindowAreNot() {
        let before = [ChromeTab(windowID: 9, tabIndex: 1, url: "https://youtube.com/watch?v=old")]
        let protected = Set(before.map(ChromeScripts.protectionKey))
        let now = [
            ChromeTab(windowID: 9, tabIndex: 1, url: "https://reddit.com/"),                 // new tab, shifted index
            ChromeTab(windowID: 9, tabIndex: 2, url: "https://youtube.com/watch?v=old"),     // pre-existing
            ChromeTab(windowID: 50, tabIndex: 1, url: "https://youtube.com/watch?v=old"),    // same URL, new window
        ]
        XCTAssertEqual(ChromeScripts.tabsToClose(now, allowedDomains: ["piazza.com"], protected: protected), [
            ChromeTab(windowID: 9, tabIndex: 1, url: "https://reddit.com/"),
            ChromeTab(windowID: 50, tabIndex: 1, url: "https://youtube.com/watch?v=old"),
        ])
    }
}
