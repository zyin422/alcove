import XCTest
@testable import Tofu

final class ClosedBrowserStateTests: XCTestCase {
    private func tab(_ url: String, window: String, index: Int, id: String) -> ChromeTab {
        ChromeTab(windowID: ScriptID(window), tabIndex: index, tabID: ScriptID(id), title: "", url: url)
    }

    func testChromeRemembersEachWindowsTabsInOrder() {
        let tabs = [tab("https://b.com", window: "1", index: 2, id: "11"),
                    tab("https://a.com", window: "1", index: 1, id: "10"),
                    tab("chrome://newtab/", window: "2", index: 1, id: "20"),
                    tab("https://c.com", window: "2", index: 2, id: "21")]
        XCTAssertEqual(ClosedBrowserState.windows(from: tabs, browser: .chrome),
                       [["https://a.com", "https://b.com"], ["https://c.com"]])
    }

    func testArcRemembersOneWindow() {
        let tabs = [tab("https://a.com", window: "W1", index: 1, id: "T1"),
                    tab("https://b.com", window: "W1", index: 2, id: "T2"),
                    tab("https://a.com", window: "W2", index: 1, id: "T3")]
        XCTAssertEqual(ClosedBrowserState.windows(from: tabs, browser: .arc), [["https://a.com", "https://b.com"]])
    }

    func testReopenBackToFrontWithClosedTabsLastSkippingOpenPages() {
        let state = ClosedBrowserState(browser: .chrome,
                                       windows: [["https://front.com"], ["https://back.com", "https://cs128.org"]],
                                       closedTabs: ["https://youtube.com", "https://front.com"])
        XCTAssertEqual(state.windowsToReopen(alreadyOpen: ["https://cs128.org"]),
                       [["https://back.com"], ["https://front.com"], ["https://youtube.com"]])
    }

    func testArcReopensEverythingInOneWindow() {
        let state = ClosedBrowserState(browser: .arc, windows: [["https://a.com"]], closedTabs: ["https://b.com"])
        XCTAssertEqual(state.windowsToReopen(alreadyOpen: []), [["https://a.com", "https://b.com"]])
    }

    func testSaveLoadAndRemove() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("closed-\(UUID().uuidString).json")
        let state = ClosedBrowserState(browser: .arc, windows: [["https://a.com"]], closedTabs: [])
        ClosedBrowserState.save(state, to: url)
        XCTAssertEqual(ClosedBrowserState.load(from: url), state)
        ClosedBrowserState.save(nil, to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testClosedOffTaskTabIsRememberedAndReopenedAfterTheSession() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("closed-\(UUID().uuidString).json")
        var tabs = [tab("https://youtube.com/watch?v=1", window: "1", index: 1, id: "5")]
        var scripts: [String] = []
        let separator = String(ChromeScripts.fieldSeparator)
        let controller = ChromeController(
            judge: FakeJudge(), prompter: FakePrompter(), alwaysBlocked: ["youtube.com"], rememberedURL: url,
            runScript: { source in
                scripts.append(source)
                if source == ChromeScripts.listTabs {
                    return .success(tabs.map { [$0.windowID.raw, String($0.tabIndex), $0.tabID.raw, $0.title, $0.url]
                        .joined(separator: separator) }.joined(separator: "\n"))
                }
                if source.contains("close (every tab") { tabs = [] }
                return .success("")
            },
            chromeIsRunning: { true })
        controller.startTabWatch(subject: "CS128", studySites: ["https://cs128.org"])
        controller.pollTabs()
        controller.stopTabWatch()
        XCTAssertEqual(ClosedBrowserState.load(from: url)?.closedTabs, ["https://youtube.com/watch?v=1"])

        scripts = []
        controller.restoreAfterSession()
        XCTAssertTrue(scripts.contains { $0.contains("https://youtube.com/watch?v=1") && $0.contains("make new window") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(controller.hasLeftovers)
    }

    @MainActor func testArcReopensClosedTabsInTheWindowAlreadyOpen() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("closed-\(UUID().uuidString).json")
        let separator = String(ChromeScripts.fieldSeparator)
        var scripts: [String] = []
        var stillOpen = true
        let controller = ChromeController(
            judge: FakeJudge(), prompter: FakePrompter(), alwaysBlocked: ["youtube.com"],
            rememberedURL: url, browser: .arc,
            runScript: { source in
                scripts.append(source)
                if source.contains("set sepChar") {
                    guard stillOpen else { return .success("") }
                    let line = ["W-1", "1", "T-1", "", "https://youtube.com/watch?v=1"].joined(separator: separator)
                    return .success(line)
                }
                return .success("")
            },
            chromeIsRunning: { true })
        controller.startTabWatch(subject: "CS128", studySites: ["https://cs128.org"])
        controller.stopTabWatch()
        stillOpen = false

        scripts = []
        controller.restoreAfterSession()
        let reopen = scripts.first { $0.contains("https://youtube.com/watch?v=1") && $0.contains("make new tab") }
        XCTAssertNotNil(reopen)
        XCTAssertTrue(reopen?.contains("if (count of windows) is 0 then") == true)
        XCTAssertTrue(reopen?.contains("tell front window") == true)
        XCTAssertFalse(reopen?.contains("tell application \"Arc\"\n    make new window") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCloseScripts() {
        XCTAssertEqual(ChromeScripts.closeAllWindows(for: .chrome), "tell application \"Google Chrome\" to close every window")
        XCTAssertTrue(ChromeScripts.closeAllWindows(for: .arc).contains("close front window"))
        XCTAssertEqual(ChromeScripts.closeTabs([], browser: .arc), "")
        XCTAssertTrue(ChromeScripts.closeTabs([tab("https://a.com", window: "W", index: 1, id: "T")], browser: .arc)
            .contains("close (every tab of window id \"W\" whose id is \"T\")"))
    }
}
