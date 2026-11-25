import AppKit
import Foundation
import Observation

/// Receives lock-in announcements (the live implementation posts to Discord).
@MainActor protocol Announcing: AnyObject {
    /// Fire-and-forget; must never block or throw.
    func announce(_ content: String)
}

/// What the user tried to sneak open during a lock-in.
enum CompanionViolation: Equatable {
    case app(name: String)
    case tab(host: String)
}

/// Receives session events for the study companion overlay. All calls are fire-and-forget.
@MainActor protocol CompanionReacting: AnyObject {
    func sessionDidStart(subject: String, goalSeconds: TimeInterval?)
    /// `violations` is the session's running total of blocked apps plus closed tabs.
    func violationOccurred(_ kind: CompanionViolation, subject: String, violations: Int)
    func sessionDidEnd(outcome: SessionOutcome, subject: String)
}

/// Moves the app's own windows in and out of lock-in mode.
@MainActor protocol WindowPresenting: AnyObject {
    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?)
    /// Close mini timer, restore main window frame, bring app to front.
    func exitLocked()
    /// Brings the locked main window to the front.
    func showMainWindow()
}

extension WindowPresenting {
    func showMainWindow() {}
}

/// The lock-in state machine (spec §6): idle -> locked -> idle.
/// Orchestrates app hiding, Chrome tiling and tab watch, app blocking, Do Not Disturb, the 1 s tick,
/// the 30 s heartbeat and announcements. Every side effect goes through an injected protocol so the engine is unit-testable.
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

    /// Seconds of work since the session started, as of the last tick (0 when idle). A break does not add to this.
    var elapsed: TimeInterval {
        guard let session else { return 0 }
        let until = pauseStartedAt ?? now
        return max(0, until.timeIntervalSince(session.start) - pausedAccumulated)
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

    /// Work time required between breaks. The countdown does not move during a break.
    static let breakCooldown: TimeInterval = 25 * 60

    /// When the current break ends. Nil while monitoring is running.
    private(set) var breakEndsAt: Date?
    /// Total duration in seconds of the current break.
    private(set) var breakTotal: TimeInterval?
    /// Seconds left in the break, nil when there isn't one.
    var breakRemaining: TimeInterval? {
        guard let breakEndsAt else { return nil }
        return max(0, breakEndsAt.timeIntervalSince(now))
    }
    var isOnBreak: Bool { breakEndsAt != nil }
    /// True once 25 minutes of work have passed since the block started, or since the last break ended.
    var canTakeBreak: Bool { isLocked && !isOnBreak && elapsed >= nextBreakElapsed }

    /// Maximum active time allowed for Discord during Planning Mode (5 minutes).
    static let discordPlanningBudget: TimeInterval = 5 * 60
    /// Active time remaining for Discord during Planning Mode.
    private(set) var discordBudgetRemaining: TimeInterval = discordPlanningBudget
    /// True when the current lock-in is the 15-minute planning session.
    var isPlanningMode: Bool { subject?.id == Subject.planningID }
    /// Resolves the frontmost bundle identifier; tests replace it.
    @ObservationIgnored var activeAppBundleID: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    @ObservationIgnored weak var presenter: WindowPresenting?
    /// Called on create, every heartbeat, counter changes, and end. AppModel persists it.
    @ObservationIgnored var onSessionChanged: ((Session) -> Void)?
    /// Called once per lock-in after everything is set up (windows, Chrome, blocker, tab watch, timer, announcement).
    /// Not called when the session ended while Chrome was being prepared. AppModel starts the chat assistant here.
    @ObservationIgnored var onLockedIn: ((Subject) -> Void)?
    /// A tab was closed, an app was hidden, or the spirit should ask something. The floating circle listens.
    /// When this is set, those events are not also toasted.
    @ObservationIgnored var onSpirit: ((SpiritNotice) -> Void)?
    /// Called after a session ends, however it ends (finish, bail, goal reached, app quit), once the engine is idle again.
    @ObservationIgnored var onEnded: (() -> Void)?
    /// A site was allowed during the lock-in. AppModel saves it on the work block.
    @ObservationIgnored var onSiteAllowed: ((String) -> Void)?
    /// An app was unblocked during the lock-in. AppModel saves it on the work block.
    @ObservationIgnored var onAppAllowed: ((AllowedApp) -> Void)?
    /// Resolves an app name to an installed app. Nil result means the name is unknown. Tests replace it.
    @ObservationIgnored var lookupApp: (String) -> AllowedApp? = { _ in nil }
    /// When true, a break stops app blocking and the tab check. Default is false: the break only pauses the timer.
    @ObservationIgnored var allowsOffTaskDuringBreak: () -> Bool = { false }
    /// Called when a break begins (e.g. to pause focus audio).
    @ObservationIgnored var onBreakStarted: (() -> Void)?
    /// Called when a break finishes (e.g. to resume focus audio).
    @ObservationIgnored var onBreakEnded: (() -> Void)?
    /// The study companion overlay; nil (e.g. in tests) means no companion.
    @ObservationIgnored var companion: CompanionReacting?

    private let workspace: WorkspaceControlling
    private let blocker: AppBlocking
    private let chrome: ChromeControlling
    private let toaster: Toasting
    private let announcer: Announcing
    private let doNotDisturb: DoNotDisturbControlling
    /// True after this block asked Do Not Disturb to turn on, so the matching end turns it off.
    @ObservationIgnored private var silencing = false
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
    /// Work time excluded because a break was running. The countdown stays put until the break ends.
    @ObservationIgnored private var pausedAccumulated: TimeInterval = 0
    /// When the current break started. Nil while the countdown is moving.
    @ObservationIgnored private var pauseStartedAt: Date?
    /// Elapsed work time at which the next break can be taken. Starts at 25 minutes.
    @ObservationIgnored private var nextBreakElapsed: TimeInterval = SessionEngine.breakCooldown
    /// The allowlist from lock-in, so a break can resume blocking with the same set.
    @ObservationIgnored private var sessionAllowed: Set<String> = []
    /// True when the tab watch was started, so a break that opened the lock can resume it.
    @ObservationIgnored private var resumesTabWatch = false
    /// True when this break stopped blocking and the tab check, so ending it has to put them back.
    @ObservationIgnored private var breakOpenedTheLock = false
    /// True after the system starts sleeping. A dark wake does not clear this while the display stays off.
    @ObservationIgnored private var systemAsleep = false
    /// True while the display is off. The countdown stays put until the display is back.
    @ObservationIgnored private var displayAsleep = false
    /// When the countdown first stopped for sleep. Nil while the Mac is awake with the display on.
    @ObservationIgnored private var asleepSince: Date?
    /// `now` at the moment the 1s timer jumped. Held until did-wake or the next tick, so a closed lid is not counted.
    @ObservationIgnored private var unexplainedGapFrom: Date?
    @ObservationIgnored private var timer: Timer?
    /// Set synchronously when the goal auto-finish is scheduled so it is scheduled only once.
    @ObservationIgnored private var isEnding = false

    init(workspace: WorkspaceControlling, blocker: AppBlocking, chrome: ChromeControlling,
         toaster: Toasting, announcer: Announcing, launcher: SetupLaunching? = nil, ownBundleID: String,
         clock: @escaping () -> Date = Date.init,
         visibleFrame: @escaping () -> CGRect? = { nil },
         primaryHeight: @escaping () -> CGFloat = { 0 },
         startsTimers: Bool = true,
         doNotDisturb: DoNotDisturbControlling) {
        self.workspace = workspace
        self.blocker = blocker
        self.chrome = chrome
        self.toaster = toaster
        self.announcer = announcer
        self.doNotDisturb = doNotDisturb
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
        await lockIn(session: newSession, subject: subject, displayName: displayName, announce: true)
    }

    /// Continues a block that was still open when the process was killed. Time since the last heartbeat
    /// is left out of the countdown, the same way sleep is.
    func resume(session saved: Session, subject: Subject, displayName: String) async {
        guard !isLocked, saved.end == nil, !saved.isDemo else { return }
        var saved = saved
        let gap = max(0, clock().timeIntervalSince(saved.lastHeartbeat))
        saved.excluded += gap
        saved.lastHeartbeat = clock()
        await lockIn(session: saved, subject: subject, displayName: displayName, announce: false)
    }

    /// Puts `saved` in force: hides other apps, opens the setup, and starts the countdown where it left off.
    private func lockIn(session saved: Session, subject: Subject, displayName: String, announce: Bool) async {
        let sessionID = saved.id
        now = clock()
        session = saved
        self.subject = subject
        self.displayName = displayName
        isEnding = false
        pausedAccumulated = saved.excluded
        pauseStartedAt = nil
        systemAsleep = false
        displayAsleep = false
        asleepSince = nil
        unexplainedGapFrom = nil
        breakOpenedTheLock = false
        announcedHalfway = false
        announcedTenMinutes = false
        nextBreakElapsed = Self.breakCooldown
        if subject.id == Subject.planningID {
            discordBudgetRemaining = Self.discordPlanningBudget
        }
        onSessionChanged?(saved)

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
            guard !DistractionApps.isDistraction(app.bundleID) else {
                toaster.show("\(app.name) is a blocked distraction app and cannot be launched during a focus session.")
                continue
            }
            let problem = await launcher.open(app, folder: slot.folder, bounds: bounds)
            guard session?.id == sessionID else { return }
            if let problem { toaster.show(problem) }
        }

        blocker.onBlocked = { [weak self] app in self?.recordBlocked(app) }
        sessionAllowed = allowed
        breakEndsAt = nil
        breakTotal = nil
        blocker.start(allowed: allowed)
        doNotDisturb.beginBlock()
        silencing = true

        chrome.onTabClosed = { [weak self] host in self?.recordClosedTab(host) }
        // Without Chrome (or without permission to script it) every poll would fail, so skip the watch.
        resumesTabWatch = chromeError != .notInstalled && chromeError != .automationDenied
        if resumesTabWatch {
            let tools = (subject.allowedApps + subject.slotApps).map(\.name)
            chrome.startTabWatch(subject: subject.name, details: subject.details, studySites: studySites(of: subject), allowedTools: tools)
        }

        if startsTimers { startTimer() }
        if announce {
            announcer.announce(DiscordMessages.start(name: displayName, subject: subject.name, mode: saved.mode))
        } else {
            toaster.show("Still locked in on \(subject.name).")
        }
        companion?.sessionDidStart(subject: subject.name, goalSeconds: saved.mode.goalSeconds)
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

    /// The Mac is about to sleep. The countdown stops until the display is back on.
    func macWillSleep() { beginSleep(system: true) }

    /// The display turned off. The countdown stops until `macDisplayWake()`.
    func macDisplaySleep() { beginSleep(system: false) }

    /// The Mac woke. Time asleep is left out once the display is on as well.
    /// A dark wake leaves the countdown stopped. A break stays the same length.
    /// Blocking and Do Not Disturb stay as they were.
    func macDidWake() { endSleep(system: true, catchMissed: true) }

    /// The display turned on. Time it was off is left out of the work countdown.
    func macDisplayWake() { endSleep(system: false, catchMissed: false) }

    private var sleepIsHolding: Bool { systemAsleep || displayAsleep }

    private func beginSleep(system: Bool) {
        guard isLocked else { return }
        let already = sleepIsHolding
        if system { systemAsleep = true } else { displayAsleep = true }
        if !already { asleepSince = clock() }
    }

    /// Drops one sleep reason. The closed stretch is applied when both the system and the display are awake.
    private func endSleep(system: Bool, catchMissed: Bool) {
        let woke = clock()
        if system { systemAsleep = false } else { displayAsleep = false }
        guard !sleepIsHolding else { return }
        let hadPause = asleepSince != nil
        if let started = asleepSince {
            if woke.timeIntervalSince(started) >= 3 {
                holdClosedMac(from: started, until: woke)
            } else {
                asleepSince = nil
            }
        } else if catchMissed, isLocked, woke.timeIntervalSince(now) >= 3 {
            // Sleep can suspend the process before the will-sleep notice is handled.
            holdClosedMac(from: now, until: woke)
        } else if !catchMissed {
            return
        }
        if hadPause || catchMissed {
            unexplainedGapFrom = nil
            now = woke
        }
    }

    /// Leaves `slept` out of the work countdown. A break in progress is extended by the same amount
    /// so it does not expire while the lid is shut. Does not stop blocking or Do Not Disturb.
    private func holdClosedMac(from started: Date, until woke: Date) {
        let slept = max(0, woke.timeIntervalSince(started))
        asleepSince = nil
        unexplainedGapFrom = nil
        guard slept > 0, var current = session else { return }
        if let end = breakEndsAt {
            breakEndsAt = end.addingTimeInterval(slept)
        } else {
            pausedAccumulated += slept
        }
        current.excluded += slept
        current.lastHeartbeat = woke
        session = current
        onSessionChanged?(current)
    }

    /// Updates `now` from clock, heartbeats, auto-finishes when goal reached.
    func tick() {
        let current = clock()
        if isLocked, sleepIsHolding {
            // The display is off or the Mac is asleep. Ticks keep coming on a dark wake and while the
            // screen is black; they must not move the countdown or forget that it is paused.
            return
        } else if unexplainedGapFrom != nil {
            // The timer fired again, so the jump was a stall, not the lid. Count it.
            unexplainedGapFrom = nil
        } else if startsTimers, isLocked, current.timeIntervalSince(now) >= 3 {
            // The 1s timer jumped and will-sleep was missed. Leave `now` so did-wake can drop the gap.
            unexplainedGapFrom = now
            return
        }
        now = current
        guard var currentSession = session else { return }
        if now.timeIntervalSince(currentSession.lastHeartbeat) >= Self.heartbeatInterval {
            currentSession.lastHeartbeat = now
            session = currentSession
            onSessionChanged?(currentSession)
        }
        if let breakEndsAt, now >= breakEndsAt {
            resumeMonitoring()
        }
        checkMilestones(session: currentSession)
        updateDiscordBudget()
        if goalReached && !isEnding {
            isEnding = true
            let sessionID = currentSession.id
            Task { [weak self] in
                guard let self, self.session?.id == sessionID else { return }
                await self.finish()
            }
        }
    }

    private func updateDiscordBudget() {
        guard isPlanningMode, discordBudgetRemaining > 0 else { return }
        if activeAppBundleID() == "com.hnc.Discord" {
            discordBudgetRemaining = max(0, discordBudgetRemaining - 1)
            if discordBudgetRemaining <= 0 {
                blocker.revoke("com.hnc.Discord")
                chrome.closeHost("discord.com")
                toaster.show("Discord 5-minute planning budget reached.")
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

    @ObservationIgnored private var recentDistractions: [Date] = []
    @ObservationIgnored private var lastAudioIntervention: Date?
    @ObservationIgnored private var announcedHalfway = false
    @ObservationIgnored private var announcedTenMinutes = false

    /// Voice milestone encouragement at 50% and 10 minutes remaining in goal sessions.
    private func checkMilestones(session: Session) {
        guard let goal = session.mode.goalSeconds, goal >= 20 * 60, !isOnBreak else { return }
        if elapsed >= (goal / 2.0), !announcedHalfway {
            announcedHalfway = true
            VoiceOutput.shared.speak("Halfway mark reached on \(session.subjectName). Strong progress.")
        } else if let rem = remaining, rem <= 10 * 60, rem > 60, !announcedTenMinutes {
            announcedTenMinutes = true
            VoiceOutput.shared.speak("Ten minutes left on \(session.subjectName). Finish strong.")
        }
    }

    /// Voice intervention when 3 or more distractions occur in rapid succession (< 90s).
    private func checkDistractionSpike(subjectName: String) {
        let now = clock()
        recentDistractions.append(now)
        recentDistractions.removeAll { now.timeIntervalSince($0) > 90 }

        if recentDistractions.count >= 3 {
            recentDistractions.removeAll()
            if lastAudioIntervention == nil || now.timeIntervalSince(lastAudioIntervention!) > 180 {
                lastAudioIntervention = now
                VoiceOutput.shared.speak("Distraction spike detected. Take a breath and stay with \(subjectName).")
            }
        }
    }

    private func recordBlocked(_ app: RunningAppInfo) {
        guard var current = session else { return }
        current.blockedAttempts += 1
        session = current
        if !blockedDuringSession.contains(where: { $0.bundleID == app.bundleID }) {
            blockedDuringSession.append(app)
        }
        let name = app.name.isEmpty ? app.bundleID : app.name
        if onSpirit != nil {
            onSpirit?(.appHidden(name))
        } else {
            toaster.show("🔒 \(name) is blocked during \(current.subjectName)")
        }
        companion?.violationOccurred(.app(name: name), subject: current.subjectName,
                                     violations: current.blockedAttempts + current.closedTabs)
        checkDistractionSpike(subjectName: current.subjectName)
        onSessionChanged?(current)
    }

    private func recordClosedTab(_ host: String) {
        guard var current = session else { return }
        current.closedTabs += 1
        current.closedTabHistory.append(host)
        session = current
        if onSpirit != nil {
            onSpirit?(.tabClosed(host))
        } else {
            toaster.show("Closed \(host) — not relevant to \(current.subjectName)")
        }
        companion?.violationOccurred(.tab(host: host), subject: current.subjectName,
                                     violations: current.blockedAttempts + current.closedTabs)
        checkDistractionSpike(subjectName: current.subjectName)
        onSessionChanged?(current)
    }

    // MARK: Break

    /// Pauses the countdown for `minutes` (1...15). App blocking and the tab check keep running unless
    /// `allowsOffTaskDuringBreak` is on, in which case they stop for the break and resume at the end.
    /// Available only after 25 minutes of work, then again 25 minutes after the previous break ends.
    /// Apps that were already hidden stay hidden. Returns false when a break is not available.
    @discardableResult
    func beginBreak(minutes: Int) -> Bool {
        now = clock()
        guard canTakeBreak else {
            if isLocked && !isOnBreak {
                toaster.show("A break opens after 25 minutes of work.")
            }
            return false
        }
        let clamped = min(max(minutes, 1), MirrorTurn.breakRange.upperBound)
        pauseStartedAt = now
        breakOpenedTheLock = allowsOffTaskDuringBreak()
        if breakOpenedTheLock {
            blocker.stop()
            chrome.pauseTabWatch()
        }
        breakEndsAt = now.addingTimeInterval(TimeInterval(clamped * 60))
        breakTotal = TimeInterval(clamped * 60)
        onBreakStarted?()
        VoiceOutput.shared.speak("Break started. Step away from the screen.")
        return true
    }

    /// Ends the break now and closes apps and tabs that are not part of the work block.
    func endBreak() {
        guard isOnBreak else { return }
        now = clock()
        resumeMonitoring()
    }

    private func resumeMonitoring() {
        if let started = pauseStartedAt {
            pausedAccumulated += max(0, now.timeIntervalSince(started))
            pauseStartedAt = nil
        }
        breakEndsAt = nil
        breakTotal = nil
        nextBreakElapsed = elapsed + Self.breakCooldown
        onBreakEnded?()
        VoiceOutput.shared.speak("Break is over. Time to lock back in.")
        presenter?.showMainWindow()
        let opened = breakOpenedTheLock
        breakOpenedTheLock = false
        guard opened, session != nil else { return }
        // Apps opened during an open break are hidden. Apps hidden at lock-in were never brought back.
        for id in workspace.hideOthers(allowed: sessionAllowed) where !hiddenByUs.contains(id) {
            hiddenByUs.append(id)
        }
        blocker.start(allowed: sessionAllowed)
        if resumesTabWatch, let subject {
            chrome.closeUnrelatedTabs()
            let tools = (subject.allowedApps + subject.slotApps).map(\.name)
            chrome.startTabWatch(subject: subject.name, details: subject.details, studySites: studySites(of: subject), allowedTools: tools)
        }
    }

    /// Study sites plus hosts the work block is allowed to keep open.
    /// Includes website slots and all domains associated with explicitly allowed apps.
    private func studySites(of subject: Subject) -> [String] {
        var raw: [String] = subject.sites + subject.extraDomains
        for slot in subject.slots where slot.kind == .website {
            raw.append(contentsOf: slot.urls)
        }
        let allAllowedApps = subject.allowedApps + subject.slotApps
        for app in allAllowedApps {
            raw.append(contentsOf: AllowedAppDomains.domains(for: app))
        }
        var seen = Set<String>()
        var sites: [String] = []
        for s in raw {
            if seen.insert(s).inserted {
                sites.append(s)
            }
        }
        return sites
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
        if outcome == .completed {
            VoiceOutput.shared.speak("Focus session completed. Great work on \(final.subjectName).")
        }
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
        breakTotal = nil
        pauseStartedAt = nil
        systemAsleep = false
        displayAsleep = false
        asleepSince = nil
        unexplainedGapFrom = nil
        pausedAccumulated = 0
        breakOpenedTheLock = false
        nextBreakElapsed = Self.breakCooldown
        blocker.stop()
        if silencing {
            doNotDisturb.endBlock()
            silencing = false
        }
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
            if !blockedDuringSession.isEmpty {
                let ids = blockedDuringSession.map(\.bundleID)
                workspace.unhide(ids)
                workspace.relaunch(ids)
            }
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
        companion?.sessionDidEnd(outcome: outcome, subject: final.subjectName)
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
        if let category = DistractionApps.category(of: app.bundleID) {
            if !(isPlanningMode && category == .messaging) {
                return "Cannot allow \(app.name): It is classified as a high-distraction app (\(category.rawValue)). Prohibited during focus sessions. Wait for your scheduled break or use Planning Mode."
            }
        }
        if let currentBrowser = subject?.browser, app.bundleID != currentBrowser.bundleID {
            let knownBrowsers = [Browser.chrome.bundleID, Browser.arc.bundleID, "com.apple.Safari", "org.mozilla.firefox", "com.operasoftware.Opera", "com.microsoft.edgemac", "com.brave.Browser"]
            if knownBrowsers.contains(app.bundleID) {
                return "Cannot allow \(app.name): Alternative web browsers cannot be enabled mid-session. All web work must stay inside your designated work browser (\(currentBrowser.title))."
            }
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

    /// Stray thoughts jotted down during the session.
    var parkedThoughts: [String] {
        session?.parkedThoughts ?? []
    }

    func addParkedThought(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = session else { return }
        current.parkedThoughts.append(trimmed)
        session = current
        onSessionChanged?(current)
    }

    func removeParkedThought(at index: Int) {
        guard var current = session, current.parkedThoughts.indices.contains(index) else { return }
        current.parkedThoughts.remove(at: index)
        session = current
        onSessionChanged?(current)
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

/// Builds the checklist shown after a work block. Nothing starts checked, so closing the summary
/// brings nothing back unless the user chooses it.
enum SessionRelaunch {
    static func choices(state: ClosedBrowserState?, quitApps: [RunningAppInfo],
                        blockedApps: [RunningAppInfo]) -> [RelaunchChoice] {
        var result: [RelaunchChoice] = []
        var seenURLs = Set<String>()
        if let state {
            for url in state.closedTabs where addTab(url, state: state, group: .closedTabs, selected: false,
                                                     seen: &seenURLs, into: &result) {}
            for url in state.windows.flatMap({ $0 }) where addTab(url, state: state, group: .previousTabs, selected: false,
                                                                  seen: &seenURLs, into: &result) {}
        }
        var seenApps = Set<String>()
        for app in quitApps where addApp(app, group: .quitApps, selected: false, seen: &seenApps, into: &result) {}
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
