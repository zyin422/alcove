import AppKit
import Foundation
import Observation

/// Receives lock-in announcements (the live implementation posts to Discord).
@MainActor protocol Announcing: AnyObject {
    /// Fire-and-forget; must never block or throw.
    func announce(_ content: String)
}

/// Moves the app's own windows in and out of lock-in mode.
@MainActor protocol WindowPresenting: AnyObject {
    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?)
    /// Close mini timer, restore main window frame, bring app to front.
    func exitLocked()
}

/// The lock-in state machine (spec §6): idle -> locked -> idle.
/// Orchestrates app hiding, Chrome tiling and tab watch, app blocking, the 1 s tick, the 30 s heartbeat
/// and announcements. Every side effect goes through an injected protocol so the engine is unit-testable.
@Observable @MainActor final class SessionEngine {
    static let heartbeatInterval: TimeInterval = 30

    private(set) var session: Session?
    private(set) var subject: Subject?
    private(set) var now: Date = Date()
    /// Most recently ended session (for the summary screen); nil until one ends.
    private(set) var lastEnded: Session?

    var isLocked: Bool { session != nil }

    /// Seconds since the session started, as of the last tick (0 when idle).
    var elapsed: TimeInterval {
        guard let session else { return 0 }
        return max(0, now.timeIntervalSince(session.start))
    }

    /// nil in open mode; clamped at 0.
    var remaining: TimeInterval? {
        guard let goal = session?.mode.goalSeconds else { return nil }
        return max(0, goal - elapsed)
    }

    /// Goal mode and the goal duration has elapsed.
    var goalReached: Bool {
        guard let goal = session?.mode.goalSeconds else { return false }
        return elapsed >= goal
    }

    /// Goal mode and goal not yet reached.
    var needsGiveUpPhrase: Bool {
        session?.mode.goalSeconds != nil && !goalReached
    }

    @ObservationIgnored weak var presenter: WindowPresenting?
    /// Called on create, every heartbeat, counter changes, and end. AppModel persists it.
    @ObservationIgnored var onSessionChanged: ((Session) -> Void)?
    /// Called once per lock-in after everything is set up (windows, Chrome, blocker, tab watch, timer, announcement).
    /// Not called when the session ended while Chrome was being prepared. AppModel starts the chat assistant here.
    @ObservationIgnored var onLockedIn: ((Subject) -> Void)?
    /// Called after a session ends, however it ends (finish, bail, goal reached, app quit), once the engine is idle again.
    @ObservationIgnored var onEnded: (() -> Void)?

    private let workspace: WorkspaceControlling
    private let blocker: AppBlocking
    private let chrome: ChromeControlling
    private let toaster: Toasting
    private let announcer: Announcing
    private let ownBundleID: String
    private let clock: () -> Date
    private let visibleFrame: () -> CGRect?
    private let primaryHeight: () -> CGFloat
    private let startsTimers: Bool

    @ObservationIgnored private var displayName = ""
    /// Bundle IDs this session hid at lock-in; unhidden again at the end.
    @ObservationIgnored private var hiddenByUs: [String] = []
    @ObservationIgnored private var timer: Timer?
    /// Set synchronously when the goal auto-finish is scheduled so it is scheduled only once.
    @ObservationIgnored private var isEnding = false

    init(workspace: WorkspaceControlling, blocker: AppBlocking, chrome: ChromeControlling,
         toaster: Toasting, announcer: Announcing, ownBundleID: String,
         clock: @escaping () -> Date = Date.init,
         visibleFrame: @escaping () -> CGRect? = { nil },
         primaryHeight: @escaping () -> CGFloat = { 0 },
         startsTimers: Bool = true) {
        self.workspace = workspace
        self.blocker = blocker
        self.chrome = chrome
        self.toaster = toaster
        self.announcer = announcer
        self.ownBundleID = ownBundleID
        self.clock = clock
        self.visibleFrame = visibleFrame
        self.primaryHeight = primaryHeight
        self.startsTimers = startsTimers
        self.now = clock()
    }

    // MARK: Lock in

    /// Locks in on `subject` (spec §6 "Lock in"). Ignored while a session is already running.
    func start(subject: Subject, mode: SessionMode, displayName: String) async {
        guard !isLocked else { return }
        let startDate = clock()
        let newSession = Session(subjectID: subject.id, subjectName: subject.name, mode: mode, start: startDate)
        let sessionID = newSession.id
        now = startDate
        session = newSession
        self.subject = subject
        self.displayName = displayName
        isEnding = false
        onSessionChanged?(newSession)

        let allowed = BlockPolicy.allowedSet(for: subject, ownBundleID: ownBundleID)
        hiddenByUs = workspace.hideOthers(allowed: allowed)

        var bounds: [ChromeBounds] = []
        var appFrame: CGRect?
        if let visible = visibleFrame() {
            let layout = LayoutEngine.layout(subject.preset, in: visible)
            let height = primaryHeight()
            bounds = layout.chromeFrames.map { ScreenGeometry.chromeBounds(for: $0, primaryHeight: height) }
            appFrame = layout.appFrame
        }
        presenter?.enterLocked(appFrame: appFrame)

        let chromeError = await chrome.prepare(sites: subject.sites, bounds: bounds)
        // The session may have ended (e.g. the app quit) while Chrome was being prepared.
        guard session?.id == sessionID else { return }
        if let chromeError {
            toaster.show(Self.chromeErrorMessage(chromeError))
        }

        blocker.onBlocked = { [weak self] app in self?.recordBlocked(app) }
        blocker.start(allowed: allowed)

        chrome.onTabClosed = { [weak self] host in self?.recordClosedTab(host) }
        // Without Chrome (or without permission to script it) every poll would fail, so skip the watch.
        if chromeError != .notInstalled && chromeError != .automationDenied {
            chrome.startTabWatch(subject: subject.name, studySites: subject.sites)
        }

        if startsTimers { startTimer() }
        announcer.announce(DiscordMessages.start(name: displayName, subject: subject.name, mode: mode))
        onLockedIn?(subject)
    }

    /// Toast text for a Chrome failure during lock-in (spec §12).
    static func chromeErrorMessage(_ error: ChromeError) -> String {
        switch error {
        case .notInstalled:
            return "Google Chrome not found — sites not opened"
        case .automationDenied:
            return "Allow Chrome control in System Settings › Privacy & Security › Automation"
        case .profileNotReady:
            return "Chrome wasn't ready — sites not opened"
        case .scriptFailed(let message):
            return "Chrome error: \(message)"
        }
    }

    // MARK: Give-up phrase

    /// template with "{subject}" replaced by subject name.
    func giveUpPhrase(template: String) -> String {
        template.replacingOccurrences(of: "{subject}", with: subject?.name ?? "")
    }

    /// Case-insensitive, whitespace/newline-trimmed comparison.
    func phraseMatches(_ typed: String, template: String) -> Bool {
        let expected = giveUpPhrase(template: template).trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !expected.isEmpty && actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    // MARK: Running

    /// Updates `now` from clock, heartbeats, auto-finishes when goal reached.
    func tick() {
        now = clock()
        guard var current = session else { return }
        if now.timeIntervalSince(current.lastHeartbeat) >= Self.heartbeatInterval {
            current.lastHeartbeat = now
            session = current
            onSessionChanged?(current)
        }
        if goalReached && !isEnding {
            isEnding = true
            let sessionID = current.id
            Task { [weak self] in
                guard let self, self.session?.id == sessionID else { return }
                await self.finish()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this always fires on the main thread.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func recordBlocked(_ app: RunningAppInfo) {
        guard var current = session else { return }
        current.blockedAttempts += 1
        session = current
        let name = app.name.isEmpty ? app.bundleID : app.name
        toaster.show("🔒 \(name) is blocked during \(current.subjectName)")
        onSessionChanged?(current)
    }

    private func recordClosedTab(_ host: String) {
        guard var current = session else { return }
        current.closedTabs += 1
        session = current
        toaster.show("Closed \(host) — not relevant to \(current.subjectName)")
        onSessionChanged?(current)
    }

    // MARK: End

    /// Ends as .completed (open mode, or goal reached). Posts completed message.
    func finish() async {
        finalize(.completed)
    }

    /// Ends as .bailed. Posts bailed message (goal mode) — in open mode behaves like finish().
    /// Once the goal has passed, a bail also counts as completed.
    func bail() async {
        guard isLocked else { return }
        now = clock()
        finalize(needsGiveUpPhrase ? .bailed : .completed)
    }

    /// Synchronous end for app termination: outcome .interrupted, unhide, restore Chrome, no Discord.
    func terminateNow() {
        _ = endSession(.interrupted)
    }

    /// Ends the session, then restores the UI, toasts the summary and announces it.
    private func finalize(_ outcome: SessionOutcome) {
        guard let final = endSession(outcome) else { return }
        presenter?.exitLocked()
        toaster.show("Saved: \(TimeFormat.short(final.duration)) on \(final.subjectName)")
        if outcome == .bailed, let goalMinutes = final.mode.goalMinutes {
            announcer.announce(DiscordMessages.bailed(name: displayName, subject: final.subjectName,
                                                      duration: final.duration, goalMinutes: goalMinutes,
                                                      attempts: final.blockedAttempts))
        } else {
            announcer.announce(DiscordMessages.completed(name: displayName, subject: final.subjectName,
                                                         duration: final.duration,
                                                         attempts: final.blockedAttempts,
                                                         tabs: final.closedTabs))
        }
    }

    /// Stops blocking and timers, stamps the end, unhides our hidden apps, restores Chrome windows and
    /// reports the final session. Returns nil when idle, so every end path runs at most once.
    private func endSession(_ outcome: SessionOutcome) -> Session? {
        guard var final = session else { return nil }
        timer?.invalidate()
        timer = nil
        blocker.stop()
        chrome.stopTabWatch()

        let endDate = clock()
        now = endDate
        final.end = endDate
        final.lastHeartbeat = endDate
        final.outcome = outcome

        workspace.unhide(hiddenByUs)
        hiddenByUs = []
        chrome.restoreMinimized()

        session = nil
        subject = nil
        isEnding = false
        lastEnded = final
        onSessionChanged?(final)
        onEnded?()
        return final
    }
}
