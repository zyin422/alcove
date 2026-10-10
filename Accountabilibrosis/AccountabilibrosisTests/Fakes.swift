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
    var watchedDomains: [String]?
    var stopWatchCount = 0
    var restoreCount = 0
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError? {
        preparedSites = sites
        preparedBounds = bounds
        return prepareResult
    }
    func startTabWatch(allowedDomains: [String]) { watchedDomains = allowedDomains }
    func stopTabWatch() { stopWatchCount += 1 }
    func restoreMinimized() { restoreCount += 1 }
    func simulateTabClosed(_ host: String) { onTabClosed?(host) }
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
