// AccountabilibrosisTests/Fakes.swift — REAL CODE (created in Task 10, reused by Task 11+)
import AppKit
import Foundation
@testable import Accountabilibrosis

@MainActor final class FakeWorkspace: WorkspaceControlling {
    var hideResult: [String] = []
    var hideCalls: [Set<String>] = []
    var unhideCalls: [[String]] = []
    var activated: [String] = []
    func hideOthers(allowed: Set<String>) -> [String] { hideCalls.append(allowed); return hideResult }
    func unhide(_ bundleIDs: [String]) { unhideCalls.append(bundleIDs) }
    func activate(bundleID: String) { activated.append(bundleID) }
}

@MainActor final class FakeBlocker: AppBlocking {
    var onBlocked: ((RunningAppInfo) -> Void)?
    var startedWith: Set<String>?
    var stopCount = 0
    func start(allowed: Set<String>) { startedWith = allowed }
    func stop() { stopCount += 1 }
    func simulateBlocked(_ bundleID: String, name: String = "App") {
        onBlocked?(RunningAppInfo(bundleID: bundleID, name: name, isRegular: true))
    }
}

@MainActor final class FakeChrome: ChromeControlling {
    var onTabClosed: ((String) -> Void)?
    var prepareResult: ChromeError?
    var preparedSites: [String] = []
    var preparedBounds: [ChromeBounds] = []
    var watchedSubject: String?
    var watchedSites: [String]?
    var stopWatchCount = 0
    var restoreCount = 0
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError? {
        preparedSites = sites
        preparedBounds = bounds
        return prepareResult
    }
    func startTabWatch(subject: String, studySites: [String]) {
        watchedSubject = subject
        watchedSites = studySites
    }
    func stopTabWatch() { stopWatchCount += 1 }
    func restoreMinimized() { restoreCount += 1 }
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
    private var pending: [CheckedContinuation<RelevanceVerdict, Never>] = []

    var judgedURLs: [String] { judgedPages.map(\.url) }
    var pendingCount: Int { pending.count }

    func judge(page: PageInfo, subject: String) async -> RelevanceVerdict {
        judgedPages.append(page)
        judgedSubjects.append(subject)
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

@MainActor final class FakeToaster: Toasting {
    var messages: [String] = []
    func show(_ message: String) { messages.append(message) }
}

@MainActor final class FakeAnnouncer: Announcing {
    var messages: [String] = []
    func announce(_ content: String) { messages.append(content) }
}

@MainActor final class FakePresenter: WindowPresenting {
    var entered: [CGRect?] = []
    var exitCount = 0
    func enterLocked(appFrame: CGRect?) { entered.append(appFrame) }
    func exitLocked() { exitCount += 1 }
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
    let clock = TestClock()
    let engine: SessionEngine

    init() {
        let clock = self.clock
        engine = SessionEngine(workspace: workspace, blocker: blocker, chrome: chrome, toaster: toaster,
                               announcer: announcer, ownBundleID: "com.accountabilibrosis.app",
                               clock: { clock.now },
                               visibleFrame: { CGRect(x: 0, y: 0, width: 1000, height: 800) },
                               primaryHeight: { 800 }, startsTimers: false)
        engine.presenter = presenter
    }
}
