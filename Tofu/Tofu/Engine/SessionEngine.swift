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
@Observable @MainActor final class SessionEngine: AppUnblocking {
    static let heartbeatInterval: TimeInterval = 30

    private(set) var session: Session?
    private(set) var subject: Subject?
    private(set) var now: Date = Date()
    /// Most recently ended session (for the summary screen); nil until one ends.
    private(set) var lastEnded: Session?
    /// Tabs and apps the user can choose to reopen after a session. Empty once that choice is applied.
    private(set) var relaunchOffer: [RelaunchChoice] = []

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

    /// When the current break ends. Nil while monitoring is running.
    private(set) var breakEndsAt: Date?
    /// Seconds left in the break, nil when there isn't one.
    var breakRemaining: TimeInterval? {
        guard let breakEndsAt else { return nil }
        return max(0, breakEndsAt.timeIntervalSince(now))
    }
    var isOnBreak: Bool { breakEndsAt != nil }

    @ObservationIgnored weak var presenter: WindowPresenting?
    /// Called on create, every heartbeat, counter changes, and end. AppModel persists it.
    @ObservationIgnored var onSessionChanged: ((Session) -> Void)?
    /// Called once per lock-in after everything is set up (windows, Chrome, blocker, tab watch, timer, announcement).
    /// Not called when the session ended while Chrome was being prepared. AppModel starts the chat assistant here.
    @ObservationIgnored var onLockedIn: ((Subject) -> Void)?
    /// Called after a session ends, however it ends (finish, bail, goal reached, app quit), once the engine is idle again.
    @ObservationIgnored var onEnded: (() -> Void)?
    /// A site was allowed during the lock-in. AppModel saves it on the work block.
    @ObservationIgnored var onSiteAllowed: ((String) -> Void)?
    /// An app was unblocked during the lock-in. AppModel saves it on the work block.
    @ObservationIgnored var onAppAllowed: ((AllowedApp) -> Void)?
    /// Resolves an app name to an installed app. Nil result means the name is unknown. Tests replace it.
    @ObservationIgnored var lookupApp: (String) -> AllowedApp? = { _ in nil }

    private let workspace: WorkspaceControlling
    private let blocker: AppBlocking
    private let chrome: ChromeControlling
    private let toaster: Toasting
    private let announcer: Announcing
    /// Opens the setup's apps; nil = app windows are skipped.
    private let launcher: SetupLaunching?
    private let ownBundleID: String
    private let clock: () -> Date
    private let visibleFrame: () -> CGRect?
    private let primaryHeight: () -> CGFloat
    private let startsTimers: Bool

    @ObservationIgnored private var displayName = ""
    /// Bundle IDs this session hid at lock-in; unhidden again at the end.
    @ObservationIgnored private var hiddenByUs: [String] = []
    /// Apps this session asked to quit at lock-in. Offered for relaunch when the session ends normally.
    @ObservationIgnored private var quitApps: [RunningAppInfo] = []
    /// Apps the user brought forward that were hidden as off-task. Offered, unchecked, at the end.
    @ObservationIgnored private var blockedDuringSession: [RunningAppInfo] = []
    /// The allowlist from lock-in, so a break can resume blocking with the same set.
    @ObservationIgnored private var sessionAllowed: Set<String> = []
    /// True when the tab watch was started, so a break resumes it.
    @ObservationIgnored private var resumesTabWatch = false
    @ObservationIgnored private var timer: Timer?
    /// Set synchronously when the goal auto-finish is scheduled so it is scheduled only once.
    @ObservationIgnored private var isEnding = false

    init(workspace: WorkspaceControlling, blocker: AppBlocking, chrome: ChromeControlling,
         toaster: Toasting, announcer: Announcing, launcher: SetupLaunching? = nil, ownBundleID: String,
         clock: @escaping () -> Date = Date.init,
         visibleFrame: @escaping () -> CGRect? = { nil },
         primaryHeight: @escaping () -> CGFloat = { 0 },
         startsTimers: Bool = true) {
        self.workspace = workspace
        self.blocker = blocker
        self.chrome = chrome
        self.toaster = toaster
        self.announcer = announcer
        self.launcher = launcher
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
        applyRelaunch()
        let startDate = clock()
        let newSession = Session(subjectID: subject.id, subjectName: subject.name, mode: mode, start: startDate)
        let sessionID = newSession.id
        now = startDate
        session = newSession
        self.subject = subject
        self.displayName = displayName
        isEnding = false
        onSessionChanged?(newSession)

        quitApps = []
        blockedDuringSession = []
        let allowed = BlockPolicy.allowedSet(for: subject, ownBundleID: ownBundleID)
        switch subject.unusedApps {
        case .hide:
            hiddenByUs = workspace.hideOthers(allowed: allowed)
        case .quit:
            (quitApps, hiddenByUs) = workspace.quitOthers(allowed: allowed)
        }

        let placement = LayoutEngine.placement(for: subject, visible: visibleFrame(), primaryHeight: primaryHeight())
        presenter?.enterLocked(appFrame: placement.appFrame)

        var browserWindows: [BrowserWindowPlan] = []
        var appSlots: [(slot: SetupSlot, bounds: ChromeBounds?)] = []
        for (index, slot) in subject.slots.enumerated() {
            let bounds = index < placement.slotBounds.count ? placement.slotBounds[index] : nil
            switch slot.kind {
            case .website:
                if !slot.urls.isEmpty { browserWindows.append(BrowserWindowPlan(urls: slot.urls, bounds: bounds)) }
            case .app:
                if slot.app != nil { appSlots.append((slot, bounds)) }
            }
        }

        let chromeError = await chrome.prepare(browser: subject.browser, windows: browserWindows)
        // The session may have ended (e.g. the app quit) while the browser was being prepared.
        guard session?.id == sessionID else { return }
        if let chromeError {
            toaster.show(Self.chromeErrorMessage(chromeError, browser: subject.browser))
        }
        for (slot, bounds) in appSlots {
            guard let app = slot.app, let launcher else { break }
            let problem = await launcher.open(app, folder: slot.folder, bounds: bounds)
            guard session?.id == sessionID else { return }
            if let problem { toaster.show(problem) }
        }

        blocker.onBlocked = { [weak self] app in self?.recordBlocked(app) }
        sessionAllowed = allowed
        breakEndsAt = nil
        blocker.start(allowed: allowed)

        chrome.onTabClosed = { [weak self] host in self?.recordClosedTab(host) }
        // Without Chrome (or without permission to script it) every poll would fail, so skip the watch.
        resumesTabWatch = chromeError != .notInstalled && chromeError != .automationDenied
        if resumesTabWatch {
            chrome.startTabWatch(subject: subject.name, studySites: studySites(of: subject))
        }

        if startsTimers { startTimer() }
        announcer.announce(DiscordMessages.start(name: displayName, subject: subject.name, mode: mode))
        onLockedIn?(subject)
    }

    /// Toast text for a browser failure during lock-in (spec §12).
    static func chromeErrorMessage(_ error: ChromeError, browser: Browser = .chrome) -> String {
        let name = browser == .chrome ? "Chrome" : browser.title
        switch error {
        case .notInstalled:
            return "\(browser.title) not found — sites not opened"
        case .automationDenied:
            return "Allow \(name) control in System Settings › Privacy & Security › Automation"
        case .profileNotReady:
            return "\(name) wasn't ready — sites not opened"
        case .scriptFailed(let message):
            return "\(name) error: \(message)"
        }
    }

    // MARK: Give-up phrase

    /// template with "{subject}" replaced by `name`, or by the setup name when `name` is nil.
    func giveUpPhrase(template: String, name: String? = nil) -> String {
        template.replacingOccurrences(of: "{subject}", with: name ?? subject?.name ?? "")
    }

    /// Case-insensitive, whitespace/newline-trimmed comparison.
    func phraseMatches(_ typed: String, template: String, name: String? = nil) -> Bool {
        let expected = giveUpPhrase(template: template, name: name).trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let breakEndsAt, now >= breakEndsAt {
            resumeMonitoring()
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
        if !blockedDuringSession.contains(where: { $0.bundleID == app.bundleID }) {
            blockedDuringSession.append(app)
        }
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

    // MARK: Break

    /// Pauses app blocking and the tab watch for `minutes` (1...15). The session clock keeps running.
    /// Calling it again restarts the countdown.
    func beginBreak(minutes: Int) {
        guard isLocked else { return }
        let clamped = min(max(minutes, 1), 15)
        blocker.stop()
        chrome.pauseTabWatch()
        let hidden = appsHiddenForTheBlock()
        if !hidden.isEmpty { workspace.unhide(hidden) }
        breakEndsAt = clock().addingTimeInterval(TimeInterval(clamped * 60))
        now = clock()
    }

    /// Apps this block hid at the start, plus apps hidden when the user brought them forward.
    private func appsHiddenForTheBlock() -> [String] {
        var seen = Set<String>()
        return (hiddenByUs + blockedDuringSession.map(\.bundleID)).filter { seen.insert($0).inserted }
    }

    private func resumeMonitoring() {
        breakEndsAt = nil
        guard session != nil else { return }
        // Anything opened during the break is hidden again. Quitting a second time would throw away work.
        for id in workspace.hideOthers(allowed: sessionAllowed) where !hiddenByUs.contains(id) {
            hiddenByUs.append(id)
        }
        blocker.start(allowed: sessionAllowed)
        if resumesTabWatch, let subject {
            chrome.startTabWatch(subject: subject.name, studySites: studySites(of: subject))
        }
    }

    /// Study sites plus hosts the work block is allowed to keep open.
    private func studySites(of subject: Subject) -> [String] {
        subject.sites + subject.extraDomains
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

    /// Synchronous end for app termination. A running session is interrupted and everything is restored.
    /// A session that already ended still has its bring-back list: quitting now restores all of it, because
    /// nobody is left to choose.
    func terminateNow() {
        if session != nil {
            _ = endSession(.interrupted)
            return
        }
        guard !relaunchOffer.isEmpty else { return }
        for index in relaunchOffer.indices { relaunchOffer[index].selected = true }
        applyRelaunch()
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

    /// Stops blocking and timers, stamps the end, unhides apps that were only hidden, and reports the final
    /// session. A normal end keeps closed tabs and quit apps for the user to choose; an interrupted end gives
    /// them all back. Returns nil when idle, so every end path runs at most once.
    private func endSession(_ outcome: SessionOutcome) -> Session? {
        guard var final = session else { return nil }
        timer?.invalidate()
        timer = nil
        breakEndsAt = nil
        blocker.stop()
        chrome.stopTabWatch()

        let endDate = clock()
        now = endDate
        final.end = endDate
        final.lastHeartbeat = endDate
        final.outcome = outcome

        workspace.unhide(hiddenByUs)
        hiddenByUs = []
        if outcome == .interrupted {
            // Nobody is here to choose, so give everything back.
            if !quitApps.isEmpty { workspace.relaunch(quitApps.map(\.bundleID)) }
            if !blockedDuringSession.isEmpty { workspace.unhide(blockedDuringSession.map(\.bundleID)) }
            chrome.restoreAfterSession()
            relaunchOffer = []
        } else {
            relaunchOffer = SessionRelaunch.choices(state: chrome.takeClosedBrowser(), quitApps: quitApps,
                                                    blockedApps: blockedDuringSession)
        }
        quitApps = []
        blockedDuringSession = []

        session = nil
        subject = nil
        isEnding = false
        lastEnded = final
        onSessionChanged?(final)
        onEnded?()
        return final
    }

    // MARK: Allowed during the block

    /// Remembers `host` on this work block so the tab watch leaves it open, including after a break.
    func rememberAllowedSite(_ host: String) {
        guard isLocked, var subject else { return }
        guard let host = DomainMatcher.host(of: host) else { return }
        let study = Set(subject.sites.compactMap { DomainMatcher.host(of: $0) })
        guard !study.contains(host) else { return }
        guard !subject.extraDomains.contains(where: { DomainMatcher.host(of: $0) == host }) else { return }
        subject.extraDomains.append(host)
        self.subject = subject
        onSiteAllowed?(host)
    }

    /// Unblocks the app named `name` for the rest of the session and remembers it on the work block.
    /// The returned text is what the assistant tells the model.
    func allowApp(named name: String) -> String {
        guard isLocked else { return "No work block is running." }
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Error: missing app name." }
        let running = (quitApps + blockedDuringSession).map { AllowedApp(bundleID: $0.bundleID, name: $0.name) }
        guard let app = AppNameMatch.find(query, in: running) ?? lookupApp(query) else {
            return "No app named \(query)."
        }
        sessionAllowed.insert(app.bundleID)
        blocker.allow(app.bundleID)
        workspace.unhide([app.bundleID])
        if var subject,
           !subject.allowedApps.contains(where: { $0.bundleID == app.bundleID }),
           !subject.slotApps.contains(where: { $0.bundleID == app.bundleID }) {
            subject.allowedApps.append(app)
            self.subject = subject
        }
        onAppAllowed?(app)
        return "Allowed \(app.name) for this work block."
    }

    /// Apps quit or blocked this session that are not allowed yet, for the assistant's prompt.
    var blockedAppsSummary: [String] {
        var seen = Set<String>()
        return (quitApps + blockedDuringSession).compactMap { app in
            guard seen.insert(app.bundleID).inserted, !sessionAllowed.contains(app.bundleID) else { return nil }
            let name = app.name.isEmpty ? app.bundleID : app.name
            return "\(name) — \(app.bundleID)"
        }
    }

    func setRelaunchSelection(_ id: String, selected: Bool) {
        guard let index = relaunchOffer.firstIndex(where: { $0.id == id }) else { return }
        relaunchOffer[index].selected = selected
    }

    /// Opens the checked tabs and apps, then forgets the offer. Safe to call again.
    func applyRelaunch() {
        let chosen = relaunchOffer.filter(\.selected)
        guard !relaunchOffer.isEmpty else { return }
        relaunchOffer = []
        let apps = chosen.filter { $0.kind == .app }.map(\.target)
        let urls = chosen.filter { $0.kind == .tab }.map(\.target)
        if !apps.isEmpty {
            workspace.relaunch(apps)
            workspace.unhide(apps)
        }
        if !urls.isEmpty { chrome.reopen(urls: urls) }
    }
}

/// One row on the end-of-session "bring back" list.
struct RelaunchChoice: Identifiable, Equatable {
    enum Kind: Equatable { case tab, app }
    enum Group: String, CaseIterable, Hashable {
        case closedTabs = "Tabs closed"
        case previousTabs = "Tabs put away"
        case quitApps = "Apps quit"
        case blockedApps = "Apps blocked"
    }

    var id: String
    var title: String
    var subtitle: String
    /// A tab's URL, or an app's bundle ID.
    var target: String
    var kind: Kind
    var group: Group
    var selected: Bool
}

/// Builds the checklist shown after a work block. Off-task tabs and blocked apps start unchecked;
/// tabs and apps that were only put away at the start start checked.
enum SessionRelaunch {
    static func choices(state: ClosedBrowserState?, quitApps: [RunningAppInfo],
                        blockedApps: [RunningAppInfo]) -> [RelaunchChoice] {
        var result: [RelaunchChoice] = []
        var seenURLs = Set<String>()
        if let state {
            for url in state.closedTabs where addTab(url, state: state, group: .closedTabs, selected: false,
                                                     seen: &seenURLs, into: &result) {}
            for url in state.windows.flatMap({ $0 }) where addTab(url, state: state, group: .previousTabs, selected: true,
                                                                  seen: &seenURLs, into: &result) {}
        }
        var seenApps = Set<String>()
        for app in quitApps where addApp(app, group: .quitApps, selected: true, seen: &seenApps, into: &result) {}
        for app in blockedApps where addApp(app, group: .blockedApps, selected: false, seen: &seenApps, into: &result) {}
        return result
    }

    private static func addTab(_ url: String, state: ClosedBrowserState, group: RelaunchChoice.Group, selected: Bool,
                               seen: inout Set<String>, into result: inout [RelaunchChoice]) -> Bool {
        guard ClosedBrowserState.isReopenable(url), seen.insert(url).inserted else { return false }
        let host = DomainMatcher.host(of: url) ?? url
        let stored = state.pageTitles[url]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        result.append(RelaunchChoice(id: "tab:\(url)", title: stored.isEmpty ? host : stored, subtitle: host,
                                     target: url, kind: .tab, group: group, selected: selected))
        return true
    }

    private static func addApp(_ app: RunningAppInfo, group: RelaunchChoice.Group, selected: Bool,
                               seen: inout Set<String>, into result: inout [RelaunchChoice]) -> Bool {
        guard !app.bundleID.isEmpty, seen.insert(app.bundleID).inserted else { return false }
        let name = app.name.isEmpty ? app.bundleID : app.name
        result.append(RelaunchChoice(id: "app:\(app.bundleID)", title: name, subtitle: app.bundleID,
                                     target: app.bundleID, kind: .app, group: group, selected: selected))
        return true
    }
}

/// Finds an installed app from a name or bundle ID the assistant was given.
enum AppNameMatch {
    /// Exact name or bundle ID, otherwise the single app whose name contains the query (or the other way around).
    static func find(_ query: String, in apps: [AllowedApp]) -> AllowedApp? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if let exact = apps.first(where: {
            $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                || $0.bundleID.compare(query, options: .caseInsensitive) == .orderedSame
        }) {
            return exact
        }
        let contains = apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || query.localizedCaseInsensitiveContains($0.name)
        }
        return contains.count == 1 ? contains[0] : nil
    }
}
