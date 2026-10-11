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

    func testCloseTabTargetsTabByIDInWindowID() {
        XCTAssertEqual(ChromeScripts.closeTab(windowID: 12, tabID: 345),
                       #"tell application "Google Chrome" to close (every tab of window id "12" whose id is 345)"#)
    }

    func testRestoreUnminimizesEachIDInsideTry() {
        let script = ChromeScripts.restore(windowIDs: [5, 9])
        XCTAssertTrue(script.contains(#"set minimized of window id "5" to false"#))
        XCTAssertTrue(script.contains(#"set minimized of window id "9" to false"#))
        XCTAssertEqual(script.components(separatedBy: "try").count - 1, 4)   // 2 × "try" + 2 × "end try"
    }

    func testMinimizeMinimizesEachIDInsideTry() {
        let script = ChromeScripts.minimize(windowIDs: [5, 9])
        XCTAssertTrue(script.hasPrefix(#"tell application "Google Chrome""#))
        XCTAssertTrue(script.contains(#"set minimized of window id "5" to true"#))
        XCTAssertTrue(script.contains(#"set minimized of window id "9" to true"#))
        XCTAssertFalse(script.contains("to false"))
        XCTAssertEqual(script.components(separatedBy: "try").count - 1, 4)   // 2 × "try" + 2 × "end try"
        XCTAssertTrue(script.hasSuffix("end tell"))
    }

    func testMinimizeWithNoIDsIsEmptyScript() {
        XCTAssertEqual(ChromeScripts.minimize(windowIDs: []), "")
    }

    func testListTabsUsesUnitSeparatorAndLinefeedCapturedOutsideTell() {
        let script = ChromeScripts.listTabs
        XCTAssertTrue(script.hasPrefix("set sepChar to ASCII character 31\nset lineChar to linefeed"))
        XCTAssertEqual(ChromeScripts.fieldSeparator, Character(UnicodeScalar(31)))
        XCTAssertTrue(script.contains("(id of t) as text"))
        XCTAssertTrue(script.contains("(title of t) as text"))
        XCTAssertTrue(script.contains("(URL of t) as text"))
    }

    func testListTabsPutsTheURLLast() {
        let script = ChromeScripts.listTabs
        let title = script.range(of: "(title of t)")
        let url = script.range(of: "(URL of t)")
        XCTAssertNotNil(title)
        XCTAssertNotNil(url)
        if let title, let url { XCTAssertLessThan(title.lowerBound, url.lowerBound) }
    }

    func testMinimizeAllAndPingTargetChrome() {
        XCTAssertTrue(ChromeScripts.minimizeAll.contains("set minimized of w to true"))
        XCTAssertTrue(ChromeScripts.minimizeAll.contains(#"set AppleScript's text item delimiters to ",""#))
        XCTAssertEqual(ChromeScripts.ping, #"tell application "Google Chrome" to count windows"#)
    }

    // MARK: parseTabs

    /// One `listTabs` output line: fields joined by the unit separator.
    private func line(_ fields: String...) -> String {
        fields.joined(separator: String(ChromeScripts.fieldSeparator))
    }

    func testParseTabsMultipleLinesWithTrailingNewline() {
        let output = [
            line("101", "1", "11", "Piazza", "https://piazza.com/class/x"),
            line("101", "2", "12", "YouTube", "https://www.youtube.com/watch?v=1"),
            line("202", "1", "21", "New Tab", "chrome://newtab/"),
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 101, tabIndex: 1, tabID: 11, title: "Piazza", url: "https://piazza.com/class/x"),
            ChromeTab(windowID: 101, tabIndex: 2, tabID: 12, title: "YouTube", url: "https://www.youtube.com/watch?v=1"),
            ChromeTab(windowID: 202, tabIndex: 1, tabID: 21, title: "New Tab", url: "chrome://newtab/"),
        ])
    }

    func testParseTabsSkipsMalformedLines() {
        let output = [
            "garbage",
            line("1", "2", "3"),                          // too few fields
            line("1", "2", "3", "t"),                      // still too few: no URL
            line("x", "1", "5", "t", "https://a.com"),     // window id not an integer
            line("1", "y", "5", "t", "https://b.com"),     // index not an integer
            line("1", "2", "z", "t", "https://c.com"),     // tab id not an integer
            "",
            line("7", "3", "9", "OK", "https://ok.com"),
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output),
                       [ChromeTab(windowID: 7, tabIndex: 3, tabID: 9, title: "OK", url: "https://ok.com")])
    }

    func testParseTabsKeepsURLWithSpacesAndHandlesCRLF() {
        let output = line("3", "1", "4", "My Notes", "file:///Users/me/My Notes.pdf") + "\r\n"
            + line("3", "2", "5", "A", "https://a.com")
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 3, tabIndex: 1, tabID: 4, title: "My Notes", url: "file:///Users/me/My Notes.pdf"),
            ChromeTab(windowID: 3, tabIndex: 2, tabID: 5, title: "A", url: "https://a.com"),
        ])
    }

    func testParseTabsKeepsTabsAndEmptyTitles() {
        let output = line("1", "1", "2", "Col1\tCol2", "https://a.com") + "\n" + line("1", "2", "3", "", "https://b.com")
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 1, tabIndex: 1, tabID: 2, title: "Col1\tCol2", url: "https://a.com"),
            ChromeTab(windowID: 1, tabIndex: 2, tabID: 3, title: "", url: "https://b.com"),
        ])
    }

    func testParseTabsRejoinsATitleThatContainsTheSeparatorAndKeepsTheRealURL() {
        let output = line("1", "1", "2", "evil", "title", "https://reddit.com/")
        XCTAssertEqual(ChromeScripts.parseTabs(output),
                       [ChromeTab(windowID: 1, tabIndex: 1, tabID: 2, title: "evil title", url: "https://reddit.com/")])
    }

    func testParseTabsOnlySplitsLinesOnCRAndLFNotOnUnicodeLineSeparators() {
        let output = line("1", "1", "2", "a\u{2028}b", "https://a.com")
        XCTAssertEqual(ChromeScripts.parseTabs(output),
                       [ChromeTab(windowID: 1, tabIndex: 1, tabID: 2, title: "a\u{2028}b", url: "https://a.com")])
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

    // MARK: protectionKey

    func testProtectionKeyIsWindowAndURL() {
        XCTAssertEqual(ChromeScripts.protectionKey(ChromeTab(windowID: 9, tabIndex: 4, tabID: 77, title: "A", url: "https://a.com")),
                       "9\thttps://a.com")
    }

    func testProtectionKeyIgnoresIndexTabIDAndTitle() {
        let before = ChromeTab(windowID: 9, tabIndex: 1, tabID: 5, title: "Old title", url: "https://a.com")
        let after = ChromeTab(windowID: 9, tabIndex: 3, tabID: 5, title: "New title", url: "https://a.com")
        XCTAssertEqual(ChromeScripts.protectionKey(before), ChromeScripts.protectionKey(after))
    }
}
