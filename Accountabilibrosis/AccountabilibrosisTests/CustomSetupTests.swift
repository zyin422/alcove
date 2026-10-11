import XCTest
@testable import Accountabilibrosis

/// Customizable setups: Arc scripts, window slots, custom layouts, the workspace capture helpers,
/// and what the engine does with app windows and "Quit them".
final class CustomSetupTests: XCTestCase {
    private let vscode = AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")

    // MARK: Subject

    func testOldSubjectDecodesAsChromeWebsiteSlots() throws {
        let id = UUID()
        let json = """
            {"id":"\(id.uuidString)","name":"CS128","preset":"split","sites":["https://cs128.org","https://prairielearn.org"],
             "allowedApps":[],"extraDomains":[],"createdAt":0}
            """
        let subject = try JSONDecoder().decode(Subject.self, from: Data(json.utf8))
        XCTAssertEqual(subject.slots.map(\.kind), [.website, .website])
        XCTAssertEqual(subject.slots.map(\.urls), [["https://cs128.org"], ["https://prairielearn.org"]])
        XCTAssertEqual(subject.browser, .chrome)
        XCTAssertEqual(subject.unusedApps, .hide)
        XCTAssertFalse(subject.usesCustomLayout)
    }

    func testSubjectRoundTripsSlotsAndChoices() throws {
        let subject = Subject(name: "CS128", sites: ["https://cs128.org"],
                              slots: [.website(["https://cs128.org"], frame: UnitRect(x: 0, y: 0, width: 0.5, height: 1)),
                                      .app(vscode, folder: "~/code/cs128")],
                              usesCustomLayout: true, browser: .arc, unusedApps: .quit)
        let decoded = try JSONDecoder().decode(Subject.self, from: JSONEncoder().encode(subject))
        XCTAssertEqual(decoded, subject)
    }

    func testAllowedSetUsesTheSetupBrowserAndApps() {
        let subject = Subject(name: "CS128", slots: [.app(vscode)], browser: .arc)
        let allowed = BlockPolicy.allowedSet(for: subject, ownBundleID: "own")
        XCTAssertTrue(allowed.contains(Browser.arc.bundleID))
        XCTAssertFalse(allowed.contains(Browser.chrome.bundleID))
        XCTAssertTrue(allowed.contains(vscode.bundleID))
        XCTAssertTrue(allowed.contains("own"))
    }

    // MARK: Validator

    func testSlotErrors() {
        XCTAssertEqual(SubjectValidator.errors(name: "", slots: [.website([""]), .app(vscode)], customLayout: false),
                       ["Name is required", "Window 1 needs a website"])
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: [SetupSlot(kind: .app)], customLayout: false),
                       ["Window 1 needs an app"])
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: [.website(["cs128.org", "not a url"])], customLayout: false),
                       ["Window 1 has a website that is not a valid URL"])
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: [], customLayout: true),
                       ["Capture your windows, or pick a layout"])
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: [.website(["cs128.org", ""])], customLayout: false), [])
    }

    func testSlotsForSaveNormalizesAndSitesCollectsWebsites() {
        let saved = SubjectValidator.slotsForSave([.website(["cs128.org", "", "https://cs128.org/a"]),
                                                   .app(vscode, folder: "  "),
                                                   .website(["cs128.org"])])
        XCTAssertEqual(saved[0].urls, ["https://cs128.org", "https://cs128.org/a"])
        XCTAssertNil(saved[1].folder)
        XCTAssertEqual(SubjectValidator.sites(of: saved), ["https://cs128.org", "https://cs128.org/a"])
    }

    // MARK: Geometry and placement

    func testUnitRectRoundTrip() {
        let visible = CGRect(x: 0, y: 60, width: 1000, height: 740)   // Dock 60 pt, menu bar none
        let bounds = ScreenGeometry.bounds(for: UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                                           visible: visible, primaryHeight: 800)
        XCTAssertEqual(bounds, ChromeBounds(left: 500, top: 0, right: 1000, bottom: 370))
        let unit = ScreenGeometry.unitRect(for: bounds.rect, visible: visible, primaryHeight: 800)
        XCTAssertEqual(unit, UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    func testUnitRectClampsToTheVisibleArea() {
        let unit = ScreenGeometry.unitRect(for: CGRect(x: -100, y: 0, width: 600, height: 2000),
                                           visible: CGRect(x: 0, y: 0, width: 1000, height: 800), primaryHeight: 800)
        XCTAssertEqual(unit, UnitRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    func testPresetPlacementGivesEachSlotItsZone() {
        let subject = Subject(name: "A", preset: .thirds, slots: [.app(vscode), .website(["https://a.com"])])
        let placement = LayoutEngine.placement(for: subject, visible: CGRect(x: 0, y: 0, width: 999, height: 800),
                                               primaryHeight: 800)
        XCTAssertEqual(placement.slotBounds, [ChromeBounds(left: 333, top: 0, right: 666, bottom: 800),
                                              ChromeBounds(left: 666, top: 0, right: 999, bottom: 800)])
        XCTAssertEqual(placement.appFrame, CGRect(x: 0, y: 0, width: 333, height: 800))
    }

    func testCustomPlacementUsesSlotFramesAndNoAppZone() {
        let subject = Subject(name: "A", slots: [.app(vscode, frame: UnitRect(x: 0, y: 0, width: 0.25, height: 1)),
                                                 .website(["https://a.com"])],
                              usesCustomLayout: true)
        let placement = LayoutEngine.placement(for: subject, visible: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                               primaryHeight: 800)
        XCTAssertEqual(placement.slotBounds, [ChromeBounds(left: 0, top: 0, right: 250, bottom: 800), nil])
        XCTAssertNil(placement.appFrame)
    }

    // MARK: Arc scripts

    func testArcOpenWindowAddsTabsAndNoBounds() {
        let script = ChromeScripts.openWindow(urls: ["https://a.com", "https://b.com"],
                                              bounds: ChromeBounds(left: 0, top: 0, right: 10, bottom: 10), browser: .arc)
        XCTAssertTrue(script.hasPrefix("tell application \"Arc\""))
        XCTAssertFalse(script.contains("bounds"))
        let b = script.range(of: "https://b.com")!.lowerBound
        let a = script.range(of: "https://a.com")!.lowerBound
        XCTAssertLessThan(b, a, "Arc shows the last tab made, so the first URL is made last")
        XCTAssertFalse(script.contains("set w to"), "Arc's make new window returns no window")
        XCTAssertTrue(script.contains("tell front window"))
        XCTAssertTrue(script.contains("if already is false then make new tab"), "an open URL is not made again")
        XCTAssertEqual(script.components(separatedBy: "make new window").count - 1, 1)
    }

    func testArcOpensEverySiteOnceInOneWindow() {
        let plans = ChromeController.openingPlans(browser: .arc, windows: [
            BrowserWindowPlan(urls: ["https://a.com", "cs128.org", "https://a.com"], bounds: nil),
            BrowserWindowPlan(urls: ["https://cs128.org", "https://b.com"],
                              bounds: ChromeBounds(left: 0, top: 0, right: 10, bottom: 10)),
        ])
        XCTAssertEqual(plans, [BrowserWindowPlan(urls: ["https://a.com", "https://cs128.org", "https://b.com"],
                                                 bounds: ChromeBounds(left: 0, top: 0, right: 10, bottom: 10))])
    }

    func testArcListTabsSurvivesATabThatWillNotAnswer() {
        let script = ChromeScripts.listTabs(for: .arc)
        XCTAssertTrue(script.contains("repeat with t in tabs of w"))
        XCTAssertFalse(script.contains("item i of tabList"))
        XCTAssertTrue(script.contains("end try"))
    }

    func testArcTabsListedByEveryWindowAreKeptOnce() {
        let us = String(ChromeScripts.fieldSeparator)
        let output = [["W-1", "1", "T-1", "", "https://a.com"], ["W-1", "2", "T-2", "", "https://b.com"],
                      ["W-2", "1", "T-1", "", "https://a.com"]]
            .map { $0.joined(separator: us) }.joined(separator: "\n")
        XCTAssertEqual(ChromeScripts.parseTabs(output, browser: .arc).map(\.tabID), ["T-1", "T-2"])
        XCTAssertEqual(ChromeScripts.parseTabs(output, browser: .arc).map(\.windowID), ["W-1", "W-1"])
    }

    func testAtMostFourWindows() {
        let five = (0..<5).map { _ in SetupSlot.website(["a.com"]) }
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: five, customLayout: true), ["Use at most 4 windows"])
        XCTAssertEqual(SubjectValidator.errors(name: "A", slots: Array(five.prefix(4)), customLayout: true), [])
    }

    func testChromeOpenWindowWithExtraTabs() {
        let script = ChromeScripts.openWindow(urls: ["https://a.com", "https://b.com"],
                                              bounds: ChromeBounds(left: 0, top: 0, right: 10, bottom: 10), browser: .chrome)
        XCTAssertTrue(script.contains("set URL of active tab of w to \"https://a.com\""))
        XCTAssertTrue(script.contains("make new tab at end of tabs of w with properties {URL:\"https://b.com\"}"))
        XCTAssertTrue(script.contains("set active tab index of w to 1"))
        XCTAssertTrue(script.contains("set bounds of w to {0, 0, 10, 10}"))
    }

    func testArcListsOnlyUnpinnedTabsAndQuotesTextIDs() {
        XCTAssertTrue(ChromeScripts.listTabs(for: .arc).contains("is \"unpinned\""))
        XCTAssertFalse(ChromeScripts.listTabs(for: .chrome).contains("unpinned"))
        XCTAssertEqual(ChromeScripts.closeTab(windowID: "W-1", tabID: "T-9", browser: .arc),
                       "tell application \"Arc\" to close (every tab of window id \"W-1\" whose id is \"T-9\")")
    }

    func testParseTabsAcceptsArcTextIDsOnlyForArc() {
        let line = ["W-1", "2", "T-9", "Title", "https://a.com"].joined(separator: String(ChromeScripts.fieldSeparator))
        XCTAssertEqual(ChromeScripts.parseTabs(line, browser: .arc).map(\.tabID), ["T-9"])
        XCTAssertEqual(ChromeScripts.parseTabs(line, browser: .chrome), [])
        XCTAssertEqual(ChromeScripts.parseIDs("W-1, W-2", browser: .arc), ["W-1", "W-2"])
        XCTAssertEqual(ChromeScripts.parseIDs("W-1, 7", browser: .chrome), [7])
    }

    func testArcTabsAreProtectedByTabID() {
        let tab = ChromeTab(windowID: "W-1", tabIndex: 1, tabID: "T-9", title: "", url: "https://a.com")
        XCTAssertEqual(ChromeScripts.protectionKey(tab), "tab\tT-9")
    }

    // MARK: Capture helpers

    func testParseCaptureKeepsWebPagesActiveTabFirst() {
        let us = "\u{1F}", rs = "\u{1E}"
        let chrome = ["0", "25", "500", "800", "2", "https://a.com\(rs)https://b.com\(rs)chrome://newtab/\(rs)https://a.com\(rs)"]
            .joined(separator: us)
        let arc = ["", "", "", "", "1", "https://c.com\(rs)https://c.com\(rs)https://d.com\(rs)"].joined(separator: us)
        let windows = WorkspaceCapture.parseCapture(chrome + "\n" + arc + "\n")
        XCTAssertEqual(windows, [
            BrowserWindowCapture(bounds: ChromeBounds(left: 0, top: 25, right: 500, bottom: 800),
                                 urls: ["https://b.com", "https://a.com"]),
            BrowserWindowCapture(bounds: nil, urls: ["https://c.com", "https://d.com"]),
        ])
    }

    func testCaptureScriptsTargetTheBrowser() {
        XCTAssertTrue(WorkspaceCapture.captureScript(for: .chrome).contains("tell application \"Google Chrome\""))
        XCTAssertTrue(WorkspaceCapture.captureScript(for: .chrome).contains("bounds of w"))
        XCTAssertTrue(WorkspaceCapture.captureScript(for: .arc).contains("tell application \"Arc\""))
        XCTAssertFalse(WorkspaceCapture.captureScript(for: .arc).contains("bounds"))
    }

    func testProjectFolderFindsTheProjectRoot() {
        let existing: Set<String> = ["/Users/me/code/cs128/.git"]
        let folder = WorkspaceCapture.projectFolder(for: URL(fileURLWithPath: "/Users/me/code/cs128/src/main.cpp"),
                                                    home: "/Users/me", isDirectory: { _ in false },
                                                    exists: { existing.contains($0) })
        XCTAssertEqual(folder, "/Users/me/code/cs128")
    }

    func testProjectFolderFallsBackToTheFilesFolder() {
        let folder = WorkspaceCapture.projectFolder(for: URL(fileURLWithPath: "/Users/me/notes/today.md"),
                                                    home: "/Users/me", isDirectory: { _ in false }, exists: { _ in false })
        XCTAssertEqual(folder, "/Users/me/notes")
        let opened = WorkspaceCapture.projectFolder(for: URL(fileURLWithPath: "/Users/me/code/app"),
                                                    home: "/Users/me", isDirectory: { _ in true }, exists: { _ in false })
        XCTAssertEqual(opened, "/Users/me/code/app")
    }

    func testAccessibilityPromptHappensOncePerBuild() {
        XCTAssertTrue(AccessibilityGate.shouldPrompt(trusted: false, stamp: "build-a", lastPrompt: nil))
        XCTAssertFalse(AccessibilityGate.shouldPrompt(trusted: false, stamp: "build-a", lastPrompt: "build-a"))
        XCTAssertTrue(AccessibilityGate.shouldPrompt(trusted: false, stamp: "build-b", lastPrompt: "build-a"))
        XCTAssertFalse(AccessibilityGate.shouldPrompt(trusted: true, stamp: "build-b", lastPrompt: nil))
        XCTAssertFalse(AccessibilityGate.shouldPrompt(trusted: false, stamp: "", lastPrompt: nil))
    }

    @MainActor func testPlacementPrefersTheWindowThatJustOpened() {
        let existing = [CGRect(x: 0, y: 0, width: 400, height: 300)]
        let frames = [existing[0],
                      CGRect(x: 10, y: 10, width: 220, height: 180),
                      CGRect(x: 700, y: 0, width: 640, height: 800)]
        XCTAssertEqual(WindowPlacer.WindowChoice.index(frames: frames, existing: existing), 2)
        let small = CGRect(x: 20, y: 20, width: 200, height: 100)
        XCTAssertEqual(WindowPlacer.WindowChoice.index(frames: [existing[0], small], existing: [existing[0], small]), 0)
        XCTAssertNil(WindowPlacer.WindowChoice.index(frames: [], existing: []))
        XCTAssertTrue(WindowPlacer.WindowChoice.matches(CGRect(x: 500, y: 25, width: 700, height: 772),
                                                        CGRect(x: 500, y: 25, width: 700, height: 800)))
        XCTAssertFalse(WindowPlacer.WindowChoice.matches(CGRect(x: 500, y: 25, width: 400, height: 300),
                                                         CGRect(x: 500, y: 25, width: 700, height: 800)))
    }

    func testFramesAreCloseWithinTolerance() {
        XCTAssertTrue(WorkspaceCapture.isClose(CGRect(x: 0, y: 25, width: 500, height: 775),
                                               CGRect(x: 2, y: 28, width: 497, height: 771)))
        XCTAssertFalse(WorkspaceCapture.isClose(CGRect(x: 0, y: 0, width: 500, height: 800),
                                                CGRect(x: 0, y: 0, width: 400, height: 800)))
    }

    func testExpandedPath() {
        XCTAssertNil(SetupLauncher.expandedPath("  "))
        XCTAssertNil(SetupLauncher.expandedPath(nil))
        XCTAssertEqual(SetupLauncher.expandedPath("/tmp/x"), "/tmp/x")
        XCTAssertFalse(SetupLauncher.expandedPath("~/code")!.hasPrefix("~"))
    }

    // MARK: Engine

    @MainActor func testStartOpensBrowserWindowsInTheSetupBrowserAndAppsInTheirZones() async {
        let h = EngineHarness()
        let subject = Subject(name: "CS128", preset: .split, sites: ["https://cs128.org"],
                              slots: [.app(vscode, folder: "~/code/cs128"),
                                      .website(["https://cs128.org", "https://cs128.org/mp1"])],
                              browser: .arc)
        await h.engine.start(subject: subject, mode: .open, displayName: "Z")
        XCTAssertEqual(h.chrome.preparedBrowser, .arc)
        XCTAssertEqual(h.chrome.preparedWindows,
                       [BrowserWindowPlan(urls: ["https://cs128.org", "https://cs128.org/mp1"],
                                          bounds: ChromeBounds(left: 500, top: 0, right: 1000, bottom: 800))])
        XCTAssertEqual(h.launcher.opened,
                       [FakeLauncher.Opened(bundleID: vscode.bundleID, folder: "~/code/cs128",
                                            bounds: ChromeBounds(left: 0, top: 0, right: 500, bottom: 800))])
        XCTAssertEqual(h.toaster.messages, [])
        XCTAssertTrue(h.engine.isLocked)
    }

    @MainActor func testLauncherProblemsAreToasted() async {
        let h = EngineHarness()
        h.launcher.problems = [vscode.bundleID: "Visual Studio Code isn't installed"]
        await h.engine.start(subject: Subject(name: "A", preset: .full, slots: [.app(vscode)]), mode: .open,
                             displayName: "Z")
        XCTAssertEqual(h.toaster.messages, ["Visual Studio Code isn't installed"])
    }

    @MainActor func testSessionEndingWhileAnAppOpensStopsTheLockIn() async {
        let h = EngineHarness()
        h.launcher.onOpen = { h.engine.terminateNow() }
        var lockedIn = false
        h.engine.onLockedIn = { _ in lockedIn = true }
        await h.engine.start(subject: Subject(name: "A", preset: .split, slots: [.app(vscode), .app(vscode)]),
                             mode: .open, displayName: "Z")
        XCTAssertEqual(h.launcher.opened.count, 1)
        XCTAssertFalse(lockedIn)
        XCTAssertNil(h.blocker.startedWith)
    }

    @MainActor func testQuitSetupQuitsOthersAndRelaunchesThemAtTheEnd() async {
        let h = EngineHarness()
        h.workspace.quitResult = (["com.spotify.client"], ["com.apple.Terminal"])
        await h.engine.start(subject: Subject(name: "A", sites: ["https://a.com"], unusedApps: .quit),
                             mode: .open, displayName: "Z")
        XCTAssertEqual(h.workspace.quitCalls.count, 1)
        XCTAssertTrue(h.workspace.hideCalls.isEmpty)
        await h.engine.finish()
        XCTAssertEqual(h.workspace.relaunchCalls, [["com.spotify.client"]])
        XCTAssertEqual(h.workspace.unhideCalls, [["com.apple.Terminal"]])
    }

    @MainActor func testHideSetupNeverQuits() async {
        let h = EngineHarness()
        await h.engine.start(subject: Subject(name: "A", sites: ["https://a.com"]), mode: .open, displayName: "Z")
        await h.engine.finish()
        XCTAssertTrue(h.workspace.quitCalls.isEmpty)
        XCTAssertEqual(h.workspace.hideCalls.count, 1)
        XCTAssertEqual(h.workspace.relaunchCalls, [[]])
    }

    @MainActor func testBrowserErrorMessages() {
        XCTAssertEqual(SessionEngine.chromeErrorMessage(.notInstalled), "Google Chrome not found — sites not opened")
        XCTAssertEqual(SessionEngine.chromeErrorMessage(.notInstalled, browser: .arc), "Arc not found — sites not opened")
        XCTAssertEqual(SessionEngine.chromeErrorMessage(.automationDenied, browser: .arc),
                       "Allow Arc control in System Settings › Privacy & Security › Automation")
    }
}
