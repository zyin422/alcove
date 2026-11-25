// TofuTests/Fakes.swift — REAL CODE (created in Task 10, reused by Task 11+)
import AppKit
import Foundation
@testable import Tofu

@MainActor final class FakeWorkspace: WorkspaceControlling {
    var hideResult: [String] = []
    var hideCalls: [Set<String>] = []
    var unhideCalls: [[String]] = []
    var activated: [String] = []
    func hideOthers(allowed: Set<String>) -> [String] { hideCalls.append(allowed); return hideResult }
    var quitResult: (quit: [RunningAppInfo], hidden: [String]) = ([], [])
    var quitCalls: [Set<String>] = []
    var relaunchCalls: [[String]] = []
    func unhide(_ bundleIDs: [String]) { unhideCalls.append(bundleIDs) }
    func activate(bundleID: String) { activated.append(bundleID) }
    func quitOthers(allowed: Set<String>) -> (quit: [RunningAppInfo], hidden: [String]) {
        quitCalls.append(allowed)
        return quitResult
    }
    func relaunch(_ bundleIDs: [String]) { relaunchCalls.append(bundleIDs) }
}

/// Records the apps a setup opens; `problems[bundleID]` is returned as the toast text.
@MainActor final class FakeLauncher: SetupLaunching {
    struct Opened: Equatable {
        var bundleID: String
        var folder: String?
        var bounds: ChromeBounds?
    }
    var opened: [Opened] = []
    var problems: [String: String] = [:]
    /// Runs inside `open`, e.g. to end the session while an app is opening.
    var onOpen: (() -> Void)?
    func open(_ app: AllowedApp, folder: String?, bounds: ChromeBounds?) async -> String? {
        onOpen?()
        opened.append(Opened(bundleID: app.bundleID, folder: folder, bounds: bounds))
        return problems[app.bundleID]
    }
}

@MainActor final class FakeBlocker: AppBlocking {
    var onBlocked: ((RunningAppInfo) -> Void)?
    var startedWith: Set<String>?
    var stopCount = 0
    private(set) var allowedBundles: [String] = []
    func start(allowed: Set<String>) { startedWith = allowed }
    func stop() { stopCount += 1 }
    func allow(_ bundleID: String) { allowedBundles.append(bundleID) }
    func revoke(_ bundleID: String) {
        allowedBundles.removeAll { $0 == bundleID }
        startedWith?.remove(bundleID)
    }
    func simulateBlocked(_ bundleID: String, name: String = "App") {
        onBlocked?(RunningAppInfo(bundleID: bundleID, name: name, isRegular: true))
    }
}

@MainActor final class FakeChrome: ChromeControlling {
    var onTabClosed: ((String) -> Void)?
    var prepareResult: ChromeError?
    /// The first URL of each prepared window.
    var preparedSites: [String] = []
    /// The bounds of the prepared windows that have one.
    var preparedBounds: [ChromeBounds] = []
    var preparedWindows: [BrowserWindowPlan] = []
    var preparedBrowser: Browser?
    var watchedSubject: String?
    var watchedDetails: String?
    var watchedSites: [String]?
    var watchedAllowedTools: [String]?
    var stopWatchCount = 0
    var restoreCount = 0
    var pendingRestore: ClosedBrowserState?
    private(set) var reopenedURLs: [String] = []
    private(set) var closedHosts: [String] = []
    private(set) var allowedHosts: [String] = []
    var onHostAllowed: ((String) -> Void)?
    /// Runs inside `prepare`, e.g. to end the session while Chrome is being prepared.
    var onPrepare: (() -> Void)?
    func prepare(browser: Browser, windows: [BrowserWindowPlan]) async -> ChromeError? {
        onPrepare?()
        preparedBrowser = browser
        preparedWindows = windows
        preparedSites = windows.compactMap(\.urls.first)
        preparedBounds = windows.compactMap(\.bounds)
        return prepareResult
    }
    func startTabWatch(subject: String, details: String, studySites: [String], allowedTools: [String] = []) {
        watchedSubject = subject
        watchedDetails = details
        watchedSites = studySites
        watchedAllowedTools = allowedTools
    }
    func pauseTabWatch() { stopWatchCount += 1 }
    private(set) var closeUnrelatedCount = 0
    func closeUnrelatedTabs() { closeUnrelatedCount += 1 }
    func stopTabWatch() { stopWatchCount += 1 }
    func restoreAfterSession() { restoreCount += 1 }
    func takeClosedBrowser() -> ClosedBrowserState? {
        let state = pendingRestore
        pendingRestore = nil
        return state
    }
    func reopen(urls: [String]) { reopenedURLs.append(contentsOf: urls) }
    func allowHost(_ host: String) {
        allowedHosts.append(host)
        onHostAllowed?(DomainMatcher.normalize(host))
    }
    func closeHost(_ host: String) { closedHosts.append(host) }
    func simulateTabClosed(_ host: String) { onTabClosed?(host) }
}

/// Answers relevance checks from a table (by URL) and records what it was asked.
/// With `holds` set, each check waits until the test calls `resolveNext`.
@MainActor final class FakeJudge: RelevanceJudging {
    var verdicts: [String: RelevanceVerdict] = [:]
    var defaultVerdict: RelevanceVerdict = .relevant
    var holds = false
    private(set) var judgedPages: [PageInfo] = []
    private(set) var judgedSubjects: [String] = []
    private(set) var judgedDetails: [String] = []
    private var pending: [CheckedContinuation<RelevanceVerdict, Never>] = []

    var judgedURLs: [String] { judgedPages.map(\.url) }
    var pendingCount: Int { pending.count }

    func judge(page: PageInfo, subject: String, details: String) async -> RelevanceVerdict {
        judgedPages.append(page)
        judgedSubjects.append(subject)
        judgedDetails.append(details)
        if holds {
            return await withCheckedContinuation { pending.append($0) }
        }
        return verdicts[page.url] ?? defaultVerdict
    }

    func resolveNext(_ verdict: RelevanceVerdict) { pending.removeFirst().resume(returning: verdict) }
}

/// Answers "is it needed?" questions from a table (by host, default Needed) and records them.
/// With `holds` set, each question waits until the test calls `resolveNext`.
@MainActor final class FakePrompter: NeedPrompting {
    var answers: [String: Bool] = [:]
    var holds = false
    private(set) var asked: [String] = []
    private(set) var askedSubjects: [String] = []
    private var pending: [CheckedContinuation<Bool, Never>] = []

    var pendingCount: Int { pending.count }

    func askIfNeeded(host: String, subject: String) async -> Bool {
        asked.append(host)
        askedSubjects.append(subject)
        if holds {
            return await withCheckedContinuation { pending.append($0) }
        }
        return answers[host] ?? true
    }

    func resolveNext(_ needed: Bool) { pending.removeFirst().resume(returning: needed) }
}

/// Records the unsure-site questions the tab watch hands to the chat assistant.
@MainActor final class FakeAsker: SiteAsking {
    private(set) var questions: [SiteQuestion] = []
    private(set) var subjects: [String] = []

    func askAboutSite(_ question: SiteQuestion, subject: String) {
        questions.append(question)
        subjects.append(subject)
    }
}

@MainActor final class FakeToaster: Toasting {
    var messages: [String] = []
    func show(_ message: String) { messages.append(message) }
}

@MainActor final class FakeAnnouncer: Announcing {
    var messages: [String] = []
    func announce(_ content: String) { messages.append(content) }
}

@MainActor final class FakeDoNotDisturb: DoNotDisturbControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    func beginBlock() { beginCount += 1 }
    func endBlock() { endCount += 1 }
}

@MainActor final class FakePresenter: WindowPresenting {
    var entered: [CGRect?] = []
    var exitCount = 0
    var showMainWindowCount = 0
    func enterLocked(appFrame: CGRect?) { entered.append(appFrame) }
    func exitLocked() { exitCount += 1 }
    func showMainWindow() { showMainWindowCount += 1 }
}

final class TestClock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_760_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Bundle of fakes + an engine wired to them (startsTimers: false; screen 1000x800 at origin, primary height 800).
@MainActor struct EngineHarness {
    let workspace = FakeWorkspace()
    let blocker = FakeBlocker()
    let chrome = FakeChrome()
    let toaster = FakeToaster()
    let announcer = FakeAnnouncer()
    let presenter = FakePresenter()
    let launcher = FakeLauncher()
    let doNotDisturb = FakeDoNotDisturb()
    let clock = TestClock()
    let engine: SessionEngine

    init() {
        let clock = self.clock
        engine = SessionEngine(workspace: workspace, blocker: blocker, chrome: chrome, toaster: toaster,
                               announcer: announcer, launcher: launcher, ownBundleID: "com.tofu.app",
                               clock: { clock.now },
                               visibleFrame: { CGRect(x: 0, y: 0, width: 1000, height: 800) },
                               primaryHeight: { 800 }, startsTimers: false,
                               doNotDisturb: doNotDisturb)
        engine.presenter = presenter
    }
}
