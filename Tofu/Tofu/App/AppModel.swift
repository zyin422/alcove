import AppKit
import Foundation
import Observation

/// What the main window's sidebar has selected.
enum SidebarItem: Hashable {
    case today
    case subject(UUID)
    case stats
    case settings
}

/// Where the Discord bot token in use comes from.
enum TokenSource: Equatable {
    /// The token saved in Settings (Keychain). It overrides the team token.
    case keychain
    /// The team token bundled from the repo's `.env` at build time.
    case teamFile
    case none

    /// Shown next to the token field in Settings.
    var label: String {
        switch self {
        case .keychain: "Using your token from Keychain"
        case .teamFile: "Using the team token from .env"
        case .none: "No token"
        }
    }

    /// Shown next to the OpenAI key field in Settings (the same three sources as the Discord token).
    var keyLabel: String {
        switch self {
        case .keychain: "Using your key from Keychain"
        case .teamFile: "Using the team key from .env"
        case .none: "No key — you'll be asked about each site"
        }
    }
}

/// Root app state: the persisted data, the sidebar selection and the session engine.
/// Every mutation saves `data` to the store right away.
@Observable @MainActor final class AppModel {
    var data: StoreData
    var selection: SidebarItem?
    let store: Store
    let engine: SessionEngine
    /// The chat screen's assistant (gpt-4.1-mini). Wired to Chrome and the session by AppModel.
    let assistant: ChatAssistant
    /// The sidebar update card's state. AppDelegate connects Sparkle in release builds.
    let updates = UpdateCenter()
    /// Brings the chat screen to the front while locked in (the assistant needs the user; the Mac woke up).
    /// AppDelegate connects it to the window presenter.
    @ObservationIgnored var onShowChat: (() -> Void)?
    /// Runs after a session ends (AppDelegate hides the voice popup).
    @ObservationIgnored var onSessionEnded: (() -> Void)?
    /// Runs when all study subjects for the day have been completed (closes between-blocks panel, etc).
    @ObservationIgnored var onStudyCompleted: (() -> Void)?
    /// Brings the main window forward when the end-of-day wrap-up opens on its own.
    @ObservationIgnored var onShowMainWindow: (() -> Void)?
    /// True while the end-of-day wrap-up sheet is up.
    var isWrappingUpDay = false
    /// True while the morning screen is up.
    var isShowingMorning = false
    /// Puts the morning screen up / takes it down (AppDelegate connects the full-screen window).
    @ObservationIgnored var onShowMorning: (() -> Void)?
    @ObservationIgnored var onHideMorning: (() -> Void)?
    /// True while the past-midnight bedtime screen is up.
    var isShowingBedtime = false
    /// Puts the bedtime screen up / takes it down (AppDelegate connects the full-screen window).
    @ObservationIgnored var onShowBedtime: (() -> Void)?
    @ObservationIgnored var onHideBedtime: (() -> Void)?
    /// Brings the morning screen back when "Start in 10 minutes" ends.
    @ObservationIgnored private var morningReturnTimer: Timer?
    /// Posts to the group chat (the same announcer the session engine uses).
    let announcer: Announcing
    /// Turns tomorrow's spoken priorities into a list.
    let priorityExtractor: PriorityExtractor
    /// The interrogation that runs when a goal is ended early.
    let mirror: MirrorInterrogator
    /// Google connection (OAuth) and the sync engine built over it; the engine is created at the end of init.
    let googleAuth: GoogleAuth
    @ObservationIgnored private(set) var googleSync: GoogleSync?
    /// Whether a Google refresh token is held; stored so Settings and Today redraw on connect, disconnect and revoke.
    private(set) var isGoogleConnected = false
    /// Transient text under the Connect button in Settings.
    var googleStatus = ""
    /// The loopback redirect of the connect flow in progress.
    @ObservationIgnored private var pendingRedirectURI = ""
    /// Where the two possible bot tokens come from (the Keychain, the bundled `.env`); tests inject fakes.
    private let keychainToken: () -> String?
    private let envToken: () -> String?
    /// Same two places for the OpenAI API key.
    private let keychainOpenAIKey: () -> String?
    private let envOpenAIKey: () -> String?

    /// Loads store (shows warning toast if any), builds live engine with real controllers.
    convenience init(store: Store = Store(fileURL: Store.defaultURL())) {
        let (loaded, isFirstLaunch) = Self.load(store)
        // The announcer and the relevance judge need the model, but the model needs the engine (which needs
        // them). Their closures read the model through this box, which is filled in after init.
        let box = ModelBox()
        let announcer = DiscordAnnouncer(
            token: { box.model?.discordToken },
            settings: { box.model?.data.settings ?? AppSettings(discordEnabled: false) },
            onCacheUpdate: { cache in box.model?.updateSettings { $0.channelCache = cache } },
            toaster: ToastCenter.shared)
        let judge = RelevanceJudge(apiKey: { [box] in box.model?.openAIKey })
        let assistant = ChatAssistant(apiKey: { [box] in box.model?.openAIKey })
        let chrome = ChromeController(judge: judge, prompter: NeedPrompt(), alwaysBlocked: DistractionList.hosts,
                                      rememberedURL: ClosedBrowserState.defaultURL())
        chrome.onHostAllowed = { host in box.model?.engine.rememberAllowedSite(host) }
        if chrome.hasLeftovers {
            // The app quit without ending a session cleanly: give back the windows and tabs it had closed.
            DispatchQueue.main.async { chrome.restoreAfterSession() }
        }
        Self.connect(assistant, with: chrome)
        let doNotDisturb = ShortcutDoNotDisturb(notify: { ToastCenter.shared.show($0) })
        let engine = SessionEngine(workspace: WorkspaceController(), blocker: AppBlocker(),
                                   chrome: chrome,
                                   toaster: ToastCenter.shared,
                                   announcer: announcer,
                                   launcher: SetupLauncher(),
                                   ownBundleID: Bundle.main.bundleIdentifier ?? "com.tofu.app",
                                   visibleFrame: { ScreenGeometry.mainVisibleFrame() },
                                   primaryHeight: { ScreenGeometry.primaryHeight() },
                                   doNotDisturb: doNotDisturb)
        engine.companion = CompanionCenter(settings: { box.model?.data.settings ?? AppSettings() })
        // Before the first block, so the Shortcuts import is not hidden by app blocking.
        DispatchQueue.main.async { doNotDisturb.prepare() }
        self.init(store: store, loaded: loaded, isFirstLaunch: isFirstLaunch, engine: engine, assistant: assistant,
                  announcer: announcer,
                  priorityExtractor: PriorityExtractor(apiKey: { [box] in box.model?.openAIKey }),
                  mirror: MirrorInterrogator(apiKey: { [box] in box.model?.openAIKey }),
                  keychainToken: { Keychain.get(service: Secrets.discordService, account: Secrets.discordAccount) },
                  envToken: { EnvFile.bundledValue(AppModel.envTokenKey) },
                  keychainOpenAIKey: { Keychain.get(service: Secrets.openAIService, account: Secrets.openAIAccount) },
                  envOpenAIKey: { EnvFile.bundledValue(AppModel.envOpenAIKeyName) },
                  googleAuth: GoogleAuth(), googleAPI: nil)
        box.model = self
        if let warning = loaded.warning {
            // After launch, so the toast panel can find the screen.
            DispatchQueue.main.async { ToastCenter.shared.show(warning) }
        }
    }

    /// Test initializer: injected engine. The token and key sources default to "nothing", so tests never
    /// read the real Keychain or the bundled `.env`; the assistant defaults to one without an API key.
    convenience init(store: Store, engine: SessionEngine,
                     keychainToken: @escaping () -> String? = { nil },
                     envToken: @escaping () -> String? = { nil },
                     keychainOpenAIKey: @escaping () -> String? = { nil },
                     envOpenAIKey: @escaping () -> String? = { nil },
                     assistant: ChatAssistant? = nil,
                     announcer: Announcing? = nil,
                     priorityExtractor: PriorityExtractor? = nil,
                     mirror: MirrorInterrogator? = nil,
                     googleAuth: GoogleAuth? = nil,
                     googleAPI: GoogleAPI? = nil) {
        let (loaded, isFirstLaunch) = Self.load(store)
        self.init(store: store, loaded: loaded, isFirstLaunch: isFirstLaunch, engine: engine,
                  assistant: assistant ?? ChatAssistant(apiKey: { nil }),
                  announcer: announcer ?? SilentAnnouncer(),
                  priorityExtractor: priorityExtractor ?? PriorityExtractor(apiKey: { nil }),
                  mirror: mirror ?? MirrorInterrogator(apiKey: { nil }),
                  keychainToken: keychainToken, envToken: envToken,
                  keychainOpenAIKey: keychainOpenAIKey, envOpenAIKey: envOpenAIKey,
                  googleAuth: googleAuth ?? GoogleAuth(readToken: { nil }, writeToken: { _ in }),
                  googleAPI: googleAPI)
    }

    private init(store: Store, loaded: StoreLoadResult, isFirstLaunch: Bool, engine: SessionEngine,
                 assistant: ChatAssistant, announcer: Announcing, priorityExtractor: PriorityExtractor,
                 mirror: MirrorInterrogator,
                 keychainToken: @escaping () -> String?, envToken: @escaping () -> String?,
                 keychainOpenAIKey: @escaping () -> String?, envOpenAIKey: @escaping () -> String?,
                 googleAuth: GoogleAuth, googleAPI: GoogleAPI?) {
        self.googleAuth = googleAuth
        self.store = store
        self.engine = engine
        self.assistant = assistant
        self.announcer = announcer
        self.priorityExtractor = priorityExtractor
        self.mirror = mirror
        self.keychainToken = keychainToken
        self.envToken = envToken
        self.keychainOpenAIKey = keychainOpenAIKey
        self.envOpenAIKey = envOpenAIKey
        self.data = loaded.data
        self.selection = loaded.data.subjects.first.map { SidebarItem.subject($0.id) }
        engine.onSessionChanged = { [weak self] session in
            self?.upsertSession(session)
        }
        // The chat lives and dies with the lock-in, and can pull the chat screen forward.
        engine.onLockedIn = { [weak self] subject in
            self?.assistant.beginSession(subject: subject.name, details: subject.details)
            BlockGuard.arm()
            if let settings = self?.data.settings, settings.focusSound != .off {
                FocusAudioEngine.shared.volume = Float(settings.focusSoundVolume)
                FocusAudioEngine.shared.play(settings.focusSound)
            }
        }
        engine.onSiteAllowed = { [weak self] host in self?.persistAllowedHost(host) }
        engine.onAppAllowed = { [weak self] app in self?.persistAllowedApp(app) }
        engine.lookupApp = { [weak self] name in self?.installedApp(named: name) }
        engine.allowsOffTaskDuringBreak = { [weak self] in
            self?.data.settings.allowOffTaskDuringBreak ?? false
        }
        engine.onBreakStarted = { FocusAudioEngine.shared.pause() }
        engine.onBreakEnded = { FocusAudioEngine.shared.resume() }
        assistant.apps = engine
        engine.onEnded = { [weak self] in
            BlockGuard.disarm()
            FocusAudioEngine.shared.stop()
            self?.assistant.endSession()
            self?.onSessionEnded?()
            self?.checkMorning()
            self?.dropShortEndedSessions()
        }
        assistant.onNeedsAttention = { [weak self] in self?.onShowChat?() }
        // First launch with a token already available (team .env or Keychain): start posting to Discord.
        if isFirstLaunch, discordToken != nil {
            data.settings.discordEnabled = true
            save()
        }
        let auth = googleAuth
        let api: GoogleAPI = googleAPI ?? GoogleClient(tokenProvider: { force in
            try await auth.accessToken(forceRefresh: force)
        })
        let sync = GoogleSync(api: api,
                              settings: { [weak self] in self?.data.settings ?? AppSettings() },
                              isConnected: { [weak self] in self?.googleAuth.isConnected ?? false },
                              plan: { [weak self] in
                                  let key = DayKey.key(for: Date())
                                  return self?.plan(for: key) ?? DayPlan(day: key)
                              },
                              applyPlan: { [weak self] plan in self?.applyGooglePlan(plan) },
                              saveCalendarID: { [weak self] id in self?.updateSettings { $0.googleCalendarID = id } },
                              onError: { message in ToastCenter.shared.show(message) })
        googleSync = sync
        isGoogleConnected = auth.isConnected
        auth.onRevoked = { [weak self] in
            self?.isGoogleConnected = false
            self?.googleSync?.stop()
        }
        if auth.isConnected { sync.start() }
        assignChartColors()
        syncAutoLaunchAndGuardian()
        VoiceOutput.shared.voice = loaded.data.settings.kokoroVoice
        VoiceOutput.shared.volume = Float(loaded.data.settings.voiceVolume)
    }

    /// Connects the assistant and Chrome both ways: the tab watch hands unsure sites to the assistant, and the
    /// assistant's allow / close decisions go back to the tab watch. Both links are weak.
    static func connect(_ assistant: ChatAssistant, with chrome: ChromeController) {
        chrome.asker = assistant
        assistant.sites = chrome
    }

    /// Full connect flow: loopback listener, browser consent, code exchange, first sync.
    func connectGoogle() async {
        let server = LoopbackServer()
        defer { server.stop() }
        googleStatus = "Waiting for Google…"
        do {
            let gate = CallbackGate()
            let port = try server.start { code, state in
                guard let state else { return }
                // A redirect with a state but no code is Google's error redirect (the user denied access).
                let outcome: ConnectOutcome = code.map { .code($0, state) } ?? .denied
                Task { @MainActor in gate.fulfill(outcome) }
            }
            let redirectURI = "http://127.0.0.1:\(port)"
            pendingRedirectURI = redirectURI
            NSWorkspace.shared.open(googleAuth.beginAuth(redirectURI: redirectURI).url)
            let timeout = Task { @MainActor in
                try await Task.sleep(nanoseconds: 180_000_000_000)
                gate.fulfill(.timedOut)
            }
            let result = await gate.wait()
            timeout.cancel()
            let code: String, state: String
            switch result {
            case .code(let value, let returnedState): (code, state) = (value, returnedState)
            case .denied:
                googleStatus = "Google access was denied."
                return
            case .timedOut:
                googleStatus = "Timed out. Try again."
                return
            }
            try await googleAuth.handleCallback(code: code, state: state, redirectURI: pendingRedirectURI)
            googleStatus = ""
            isGoogleConnected = true
            googleSync?.start()
        } catch {
            googleStatus = "Connection failed: \(error)"
        }
    }

    /// Stops syncing and forgets the Google token.
    func disconnectGoogle() {
        googleSync?.stop()
        googleAuth.disconnect()
        isGoogleConnected = false
        googleStatus = ""
    }

    /// The display turned off. The work countdown waits until it is back.
    func displayWillSleep() {
        engine.macDisplaySleep()
    }

    /// The display is back. The countdown continues, and a new day can ask for a block.
    func displayDidWake() {
        engine.macDisplayWake()
        checkMorning()
    }

    /// The Mac is closing: freeze the work timer and the post-block grace so neither keeps counting while asleep.
    func systemWillSleep() {
        engine.macWillSleep()
        holdMorningGrace()
    }

    /// The Mac woke from sleep: the work timer and the post-block grace continue from where they stopped, and
    /// while locked in the assistant welcomes the user back (which brings up the chat).
    func systemDidWake() {
        engine.macDidWake()
        resumeMorningGrace()
        guard engine.isLocked else { return }
        assistant.greetAfterWake()
    }

    /// Loads the store and reports whether there was no store file before (a first launch).
    private static func load(_ store: Store) -> (result: StoreLoadResult, isFirstLaunch: Bool) {
        let existed = FileManager.default.fileExists(atPath: store.fileURL.path)
        return (store.load(), !existed)
    }

    // MARK: Subjects

    func subject(id: UUID) -> Subject? {
        if id == Subject.planningID {
            return Subject.planningSetup(feedURL: data.settings.aiFeedURL)
        }
        return data.subjects.first { $0.id == id }
    }

    /// Gives each class a palette color. A custom picker color snaps back; two classes never share a swatch.
    private func assignChartColors() {
        let next = SubjectColor.assigned(data.subjects.map { ($0.name, $0.colorHex) })
        var changed = false
        for index in data.subjects.indices where data.subjects[index].colorHex != next[index] {
            data.subjects[index].colorHex = next[index]
            changed = true
        }
        if changed { save() }
    }

    /// Appends the subject, selects it and saves.
    func addSubject(_ subject: Subject) {
        data.subjects.append(subject)
        selection = .subject(subject.id)
        save()
    }

    /// Saves a host the user or the assistant allowed during the current work block.
    private func persistAllowedHost(_ host: String) {
        guard let id = engine.subject?.id, id != Subject.planningID, var subject = subject(id: id) else { return }
        guard let host = DomainMatcher.host(of: host),
              !subject.extraDomains.contains(where: { DomainMatcher.host(of: $0) == host }) else { return }
        subject.extraDomains.append(host)
        updateSubject(subject)
    }

    /// Saves an app the assistant unblocked during the current work block.
    private func persistAllowedApp(_ app: AllowedApp) {
        guard let id = engine.subject?.id, id != Subject.planningID, var subject = subject(id: id) else { return }
        guard !subject.allowedApps.contains(where: { $0.bundleID == app.bundleID }),
              !subject.slotApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        subject.allowedApps.append(app)
        updateSubject(subject)
    }

    private var installedAppsCache: [AllowedApp]?

    /// An installed app matching `name`, scanned once per launch.
    private func installedApp(named name: String) -> AllowedApp? {
        if installedAppsCache == nil {
            installedAppsCache = AppCatalog.scan(directories: AppCatalog.defaultDirectories())
        }
        return AppNameMatch.find(name, in: installedAppsCache ?? [])
    }

    /// Replaces the subject with the same id (no-op if it is unknown) and saves.
    func updateSubject(_ subject: Subject) {
        guard let index = data.subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        data.subjects[index] = subject
        save()
    }

    /// Reorders subjects in the sidebar and saves. The selection stays on the same subject.
    func moveSubjects(from source: IndexSet, to destination: Int) {
        data.subjects.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Removes the subject but keeps its sessions (stats use their `subjectName` snapshot).
    func deleteSubject(id: UUID) {
        data.subjects.removeAll { $0.id == id }
        if selection == .subject(id) {
            selection = data.subjects.first.map { SidebarItem.subject($0.id) }
        }
        save()
    }

    // MARK: Sessions

    /// Drops a finished block from the record, so its time leaves the stats. Saves immediately.
    func deleteSession(id: UUID) {
        guard data.sessions.contains(where: { $0.id == id && $0.end != nil }) else { return }
        data.sessions.removeAll { $0.id == id }
        save()
    }

    /// Drops finished blocks under five minutes. Called after the morning check, so a short abort
    /// still brings the screen back, then leaves no row in stats.
    func dropShortEndedSessions() {
        let cleaned = Store.droppingShortBlocks(data)
        guard cleaned.sessions.map(\.id) != data.sessions.map(\.id) else { return }
        data.sessions = cleaned.sessions
        save()
    }

    /// Inserts a new session or replaces the one with the same id, then saves.
    func upsertSession(_ session: Session) {
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            data.sessions[index] = session
        } else {
            data.sessions.append(session)
        }
        save()
        if session.end != nil, session.outcome != nil {
            googleSync?.sessionEnded(session)
        }
    }

    /// True when an OpenAI key is available, so ending a goal early goes through the Mirror.
    var hasMirror: Bool {
        !(openAIKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the Mirror and the give-up phrase both name: the unfinished priority for this setup, else the setup.
    var mirrorTaskName: String {
        let setup = engine.subject?.name ?? engine.session?.subjectName ?? ""
        let title = todayPlan().priorities.first { !$0.isDone && $0.subjectID == engine.subject?.id }?
            .title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? setup : title
    }

    /// The facts for an interrogation. The priority is the first unfinished one tied to the running setup.
    func mirrorContext(reason: String) -> MirrorContext {
        let setup = engine.subject?.name ?? engine.session?.subjectName ?? ""
        return MirrorContext(priority: mirrorTaskName, setup: setup,
                             elapsedSeconds: Int(engine.elapsed.rounded()),
                             goalMinutes: engine.session?.mode.goalMinutes ?? 0,
                             reason: reason,
                             blockedAttempts: engine.session?.blockedAttempts ?? 0,
                             closedTabs: engine.session?.closedTabs ?? 0)
    }

    /// Starts a session on the subject using the display name from settings.
    func lockIn(subjectID: UUID, mode: SessionMode) async {
        guard let subject = subject(id: subjectID) else { return }
        let trimmed = data.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? NSFullUserName() : trimmed
        await engine.start(subject: subject, mode: mode, displayName: displayName)
    }

    // MARK: Day plan

    func plan(for day: String) -> DayPlan? {
        data.dayPlans.first { $0.day == day }
    }

    /// The plan Today shows: the current day, or the previous day when that day still needs a wrap-up.
    func todayPlan(now: Date = Date()) -> DayPlan {
        let day = DayPlanner.workingDay(now: now, plans: data.dayPlans)
        return plan(for: day) ?? DayPlan(day: day)
    }

    /// True when the previous day has a plan that was never wrapped up, so the new day has not started.
    func needsPreviousWrapUp(now: Date = Date()) -> Bool {
        DayPlanner.workingDay(now: now, plans: data.dayPlans) != DayKey.key(for: now)
    }

    /// Changes the plan of `day` (creating it when missing) and saves.
    func updatePlan(day: String, _ mutate: (inout DayPlan) -> Void) {
        let before = plan(for: day) ?? DayPlan(day: day)
        if let index = data.dayPlans.firstIndex(where: { $0.day == day }) {
            mutate(&data.dayPlans[index])
        } else {
            var plan = DayPlan(day: day)
            mutate(&plan)
            data.dayPlans.append(plan)
        }
        save()
        // The mirror targets the real calendar day, not the working day; other days only push done/undone flips.
        guard let after = plan(for: day) else { return }
        if day == DayKey.key(for: Date()) {
            googleSync?.planChanged(from: before, to: after)
        } else {
            googleSync?.pushStatusChanges(from: before, to: after)
        }
    }

    /// GoogleSync writes a pulled plan through here; unlike `updatePlan` it never reports back to the sync.
    private func applyGooglePlan(_ plan: DayPlan) {
        if let index = data.dayPlans.firstIndex(where: { $0.day == plan.day }) {
            data.dayPlans[index] = plan
        } else {
            // An empty pull never creates a plan: an empty un-wrapped day would force a wrap-up next morning.
            guard !plan.priorities.isEmpty else { return }
            data.dayPlans.append(plan)
        }
        save()
    }

    /// Ticks (or unticks) a priority of `day`. Finishing one posts an update to Discord.
    func setPriority(_ id: UUID, done: Bool, day: String) {
        var finished: Priority?
        updatePlan(day: day) { plan in
            guard let index = plan.priorities.firstIndex(where: { $0.id == id }) else { return }
            guard plan.priorities[index].isDone != done else { return }
            plan.priorities[index].isDone = done
            if done { finished = plan.priorities[index] }
        }
        if let finished {
            postPriorityUpdate(finished)
            if isStudyCompleted(day: day) {
                dismissMorning()
                onStudyCompleted?()
                ToastCenter.shared.show("All study subjects completed for today! 🎉")
            }
        }
    }

    /// True when the user has completed all study priorities or subjects planned for the given day.
    func isStudyCompleted(day: String? = nil, now: Date = Date()) -> Bool {
        let targetDay = day ?? DayKey.key(for: now)
        let todayPlan = plan(for: targetDay)
        if todayPlan?.wrappedUp == true { return true }

        let priorities = todayPlan?.priorities ?? []
        if !priorities.isEmpty {
            return priorities.allSatisfy(\.isDone)
        }

        // Fallback: If no priorities were explicitly planned for today, check if every configured
        // subject has at least one completed focus session recorded for today.
        let subjects = data.subjects
        guard !subjects.isEmpty else { return false }
        let todaysSessions = data.sessions.filter {
            !$0.isDemo && $0.end != nil && DayKey.key(for: $0.start) == targetDay
        }
        guard !todaysSessions.isEmpty else { return false }
        let completedSubjectIDs = Set(todaysSessions.map(\.subjectID))
        return subjects.allSatisfy { completedSubjectIDs.contains($0.id) }
    }

    /// The one-line update for a priority that just flipped to done. The end-of-day recap is separate.
    private func postPriorityUpdate(_ priority: Priority) {
        let setup = priority.subjectID.flatMap { subject(id: $0)?.name }
        announcer.announce(DiscordMessages.priorityUpdate(name: displayName, title: priority.title, setup: setup))
    }

    /// The unfinished priority of today that `session` (just ended) worked on, for "Did you finish …?".
    func priorityToConfirm(after session: Session, now: Date = Date()) -> Priority? {
        DayPlanner.priorityToConfirm(after: session, in: plan(for: DayKey.key(for: session.start)) ?? todayPlan(now: now))
    }

    /// Total real focus time in seconds logged for this priority on `day` (matched via subjectID).
    func focusDuration(for priority: Priority, day: String) -> TimeInterval {
        guard let subjectID = priority.subjectID else { return 0 }
        return data.sessions
            .filter { DayKey.key(for: $0.start) == day && $0.subjectID == subjectID && !$0.isDemo }
            .reduce(0) { $0 + $1.duration }
    }

    /// Opens the wrap-up when its time has come (called every minute). Marks the day as prompted.
    func checkEndOfDay(now: Date = Date()) {
        guard !isWrappingUpDay, !isShowingMorning,
              DayPlanner.shouldPromptEndOfDay(now: now, settings: data.settings, plans: data.dayPlans,
                                              isLocked: engine.isLocked) else { return }
        updateSettings { $0.lastDayPromptKey = DayKey.key(for: now) }
        isWrappingUpDay = true
        onShowMainWindow?()
    }

    // MARK: Morning

    /// A block that was still open when the process was killed is put back in force.
    func continueBlockIfNeeded() async {
        guard let open = data.sessions.last(where: { $0.end == nil && !$0.isDemo }) else {
            BlockGuard.disarm()
            return
        }
        let subject = data.subjects.first { $0.id == open.subjectID }
            ?? Subject(id: open.subjectID, name: open.subjectName)
        await engine.resume(session: open, subject: subject, displayName: data.settings.displayName)
    }

    /// Shows the morning screen when a block should start: on launch, wake, and unlock, and again after a
    /// block ends. When yesterday still needs a wrap-up, that sheet opens instead, and the new day waits.
    func checkMorning(now: Date = Date()) {
        resumeMorningGrace(now: now)
        syncGraceSession(now: now)
        if openPreviousWrapUpIfNeeded(now: now) { return }
        let today = DayKey.key(for: now)
        let isWrapped = plan(for: today)?.wrappedUp == true
        let isDone = isStudyCompleted(day: today, now: now)
        let prompt = DayPlanner.morningPrompt(
            now: now, settings: data.settings, isLocked: engine.isLocked,
            isBusy: isWrappingUpDay,
            wrappedUp: isWrapped,
            studyCompleted: isDone,
            sessions: data.sessions, quiet: DayPlanner.quietIntervals(googleSync?.todayEvents ?? []),
            graceUntil: data.settings.morningGraceUntil, graceHeld: data.settings.morningGraceHeld != nil)
        if let deadline = prompt.graceUntil, deadline != data.settings.morningGraceUntil {
            updateSettings { $0.morningGraceUntil = deadline }
        }
        scheduleMorningReturn(at: prompt.waitUntil, now: now)
        guard prompt.show else {
            if isShowingMorning && (isWrapped || isDone) {
                dismissMorning()
            }
            return
        }
        showMorning(now: now)
    }

    /// Stores the grace for a new real block. A later check pushes it past a calendar event.
    private func syncGraceSession(now: Date) {
        guard data.settings.morningGraceHeld == nil else { return }
        let today = DayKey.key(for: now)
        let todays = data.sessions.filter {
            !$0.isDemo && $0.end != nil && DayKey.key(for: $0.start) == today
        }
        guard let latest = todays.max(by: { ($0.end ?? $0.start) < ($1.end ?? $1.start) }),
              latest.duration >= DayPlanner.realBlockSeconds, let end = latest.end,
              data.settings.morningGraceSessionID != latest.id else { return }
        var deadline = end.addingTimeInterval(DayPlanner.betweenBlockGrace)
        if let event = DayPlanner.quietIntervals(googleSync?.todayEvents ?? []).first(where: { $0.start <= end && end < $0.end }) {
            deadline = event.end.addingTimeInterval(DayPlanner.betweenBlockGrace)
        }
        updateSettings {
            $0.morningGraceSessionID = latest.id
            $0.morningGraceUntil = deadline
        }
    }

    /// Freezes whatever grace is left. Closing the lid does not spend the walk.
    func holdMorningGrace(now: Date = Date()) {
        guard data.settings.morningGraceHeld == nil else { return }
        let today = DayKey.key(for: now)
        let real = data.sessions.contains {
            !$0.isDemo && $0.end != nil && DayKey.key(for: $0.start) == today && $0.duration >= DayPlanner.realBlockSeconds
        }
        guard real else { return }
        let quiet = DayPlanner.quietIntervals(googleSync?.todayEvents ?? [])
        let remaining: TimeInterval
        if quiet.contains(where: { $0.start <= now && now < $0.end }) {
            remaining = DayPlanner.betweenBlockGrace
        } else if let until = data.settings.morningGraceUntil, until > now {
            remaining = until.timeIntervalSince(now)
        } else {
            return
        }
        updateSettings { $0.morningGraceHeld = remaining }
    }

    /// Starts the frozen grace from `now`. An event still in progress keeps its own end time.
    func resumeMorningGrace(now: Date = Date()) {
        guard let held = data.settings.morningGraceHeld else { return }
        let quiet = DayPlanner.quietIntervals(googleSync?.todayEvents ?? [])
        let duringEvent = quiet.contains { $0.start <= now && now < $0.end }
        updateSettings {
            $0.morningGraceHeld = nil
            if !duringEvent {
                $0.morningGraceUntil = now.addingTimeInterval(held)
            }
        }
    }

    /// Arms the timer that brings the morning screen back. A deadline already past is left for `checkMorning`.
    private func scheduleMorningReturn(at until: Date?, now: Date) {
        morningReturnTimer?.invalidate()
        morningReturnTimer = nil
        guard let until, until > now else { return }
        let timer = Timer(timeInterval: until.timeIntervalSince(now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.morningReturnTimer = nil
                self?.checkMorning()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        morningReturnTimer = timer
    }

    /// A block is under way, so the return timer stays quiet until it ends.
    private func settleMorning(now: Date) {
        morningReturnTimer?.invalidate()
        morningReturnTimer = nil
        let key = DayKey.key(for: now)
        guard data.settings.lastMorningKey != key else { return }
        updateSettings { $0.lastMorningKey = key }
    }

    /// Opens the morning screen for the current day. If yesterday was not wrapped up, opens that wrap-up.
    func startMyDay(now: Date = Date()) {
        if openPreviousWrapUpIfNeeded(now: now) { return }
        showMorning(now: now)
    }

    /// Opens the wrap-up for the previous day when it is still open. Returns true when the new day is blocked.
    private func openPreviousWrapUpIfNeeded(now: Date) -> Bool {
        guard needsPreviousWrapUp(now: now) else { return false }
        guard !engine.isLocked, !isWrappingUpDay, !isShowingMorning else { return true }
        isWrappingUpDay = true
        onShowMainWindow?()
        return true
    }

    /// Shows the morning screen now (also from "Start my day"). The day counts as done only once a block starts.
    func showMorning(now: Date = Date()) {
        guard !engine.isLocked else { return }
        isShowingMorning = true
        onShowMorning?()
    }

    func dismissMorning() {
        guard isShowingMorning else { return }
        isShowingMorning = false
        onHideMorning?()
    }

    /// Postponing is available once per day when the user doesn't want to lock in right now.
    func allowsMorningPostpone(now: Date = Date()) -> Bool {
        let key = DayKey.key(for: now)
        return data.settings.lastPostponeKey != key
    }

    var canPostponeMorning: Bool {
        allowsMorningPostpone()
    }

    /// Hides the morning or bedtime screen for ten minutes. Available once per day.
    func postponeMorning(by seconds: TimeInterval = 10 * 60, now: Date = Date()) {
        guard allowsMorningPostpone(now: now) else { return }
        let deadline = now.addingTimeInterval(seconds)
        let key = DayKey.key(for: now)
        updateSettings {
            $0.lastPostponeKey = key
            $0.morningPostponeUntil = deadline
            $0.morningGraceUntil = deadline
        }
        dismissMorning()
        dismissBedtime()
        scheduleMorningReturn(at: deadline, now: now)
        onShowMainWindow?()
    }

    /// Opens the Plan in the main window, postponing the full-screen lock for 10 minutes (once per day).
    func openPlan(now: Date = Date()) {
        guard allowsMorningPostpone(now: now) else { return }
        postponeMorning(by: 10 * 60, now: now)
        selection = .today
        onShowMainWindow?()
    }

    /// Starts a session directly on a subject from the morning screen without tying to a priority.
    func start(subjectID: UUID, mode: SessionMode, now: Date = Date()) async {
        dismissMorning()
        await lockIn(subjectID: subjectID, mode: mode)
        if engine.isLocked {
            settleMorning(now: now)
        } else {
            checkMorning(now: now)
        }
    }

    // MARK: - Force-Block Countdown & Telemetry

    /// When the morning screen or between-block force lock-in will next take over the screen.
    /// Nil if already locked in, if the day is wrapped up, if study subjects are completed, or if past dayEndMinutes.
    var nextForceBlockDeadline: Date? {
        guard !engine.isLocked else { return nil }
        let now = Date()
        let today = DayKey.key(for: now)
        if plan(for: today)?.wrappedUp == true || isStudyCompleted(day: today, now: now) {
            return nil
        }
        let prompt = DayPlanner.morningPrompt(
            now: now, settings: data.settings, isLocked: engine.isLocked,
            isBusy: isWrappingUpDay,
            wrappedUp: false,
            studyCompleted: false,
            sessions: data.sessions,
            quiet: DayPlanner.quietIntervals(googleSync?.todayEvents ?? []),
            graceUntil: data.settings.morningGraceUntil,
            graceHeld: data.settings.morningGraceHeld != nil
        )
        if prompt.show {
            return now
        }
        guard let wait = prompt.waitUntil, wait < DayKey.nextStart(after: now) else { return nil }
        return wait
    }

    /// Remaining seconds until the next force lock-in. 0 if due now; nil if none scheduled.
    var secondsUntilNextForceBlock: TimeInterval? {
        guard let deadline = nextForceBlockDeadline else { return nil }
        return max(0, deadline.timeIntervalSince(Date()))
    }

    /// Human explanation of why the next force-block deadline is set to that time.
    var nextForceBlockReason: String? {
        guard let deadline = nextForceBlockDeadline else { return nil }
        let now = Date()
        if deadline <= now { return "Lock-in required now" }
        if let postpone = data.settings.morningPostponeUntil, postpone > now {
            return "10-minute postpone active"
        }
        let quiet = DayPlanner.quietIntervals(googleSync?.todayEvents ?? [])
        if quiet.contains(where: { $0.start <= now && now < $0.end }) {
            return "Protected calendar event"
        }
        if data.settings.morningGraceHeld != nil {
            return "Grace paused (laptop closed)"
        }
        return "Between-block recovery grace"
    }

    // MARK: - Bedtime & Planning Mode

    /// Checks if the current time is past midnight (00:00 - 04:00 AM) and locks the computer unless a block is running.
    func checkBedtime(now: Date = Date()) {
        guard DayPlanner.shouldShowBedtime(now: now, settings: data.settings, isLocked: engine.isLocked, isBusy: isWrappingUpDay) else {
            if isShowingBedtime && !DayPlanner.isPastMidnight(now: now) {
                dismissBedtime()
            }
            return
        }
        showBedtime(now: now)
    }

    func showBedtime(now: Date = Date()) {
        guard !engine.isLocked, !isShowingBedtime else { return }
        if isShowingMorning { dismissMorning() }
        isShowingBedtime = true
        onShowBedtime?()
    }

    func dismissBedtime() {
        guard isShowingBedtime else { return }
        isShowingBedtime = false
        onHideBedtime?()
    }

    /// Whether the 15-minute planning mode is available tonight (capped at once per night past midnight).
    func canPlanTonight(now: Date = Date()) -> Bool {
        let key = DayKey.key(for: now)
        return data.settings.lastMidnightPlanningKey != key
    }

    /// Whether the daytime 15-minute planning mode is available today (capped at once per day to prevent avoidance spam).
    func canPlanToday(now: Date = Date()) -> Bool {
        let key = DayKey.key(for: now)
        return data.settings.lastDayPlanningKey != key
    }

    var canPlanToday: Bool {
        canPlanToday()
    }

    /// Starts a dedicated 15-minute planning session on the system planning setup.
    func startPlanningMode(now: Date = Date(), force: Bool = false) async {
        guard force || canPlanToday(now: now) else { return }
        let key = DayKey.key(for: now)
        updateSettings { $0.lastDayPlanningKey = key }
        dismissMorning()
        dismissBedtime()
        await lockIn(subjectID: Subject.planningID, mode: .goal(minutes: 15))
    }

    /// Starts planning mode from the past-midnight bedtime screen, recording tonight's quota.
    func startPlanningFromBedtime(now: Date = Date()) async {
        guard canPlanTonight(now: now) else { return }
        let key = DayKey.key(for: now)
        updateSettings { $0.lastMidnightPlanningKey = key }
        await startPlanningMode(now: now, force: true)
    }

    /// From the morning screen: ties the priority to `subjectID` (when it had another or none), closes the
    /// screen and locks in on that setup.
    func start(priority: Priority, subjectID: UUID, mode: SessionMode, now: Date = Date()) async {
        // A carried-over priority shares its id with the previous day's copy, so today's plan wins.
        let todayKey = DayKey.key(for: now)
        let day = plan(for: todayKey)?.priorities.contains { $0.id == priority.id } == true
            ? todayKey
            : data.dayPlans.first { $0.priorities.contains { $0.id == priority.id } }?.day ?? todayKey
        if priority.subjectID != subjectID {
            updatePlan(day: day) { plan in
                guard let index = plan.priorities.firstIndex(where: { $0.id == priority.id }) else { return }
                plan.priorities[index].subjectID = subjectID
            }
        }
        await start(subjectID: subjectID, mode: mode, now: now)
    }

    /// Ends the day: stores today's ticks, saves tomorrow's priorities, and posts the recap to the group chat.
    func wrapUpDay(today snapshot: [Priority], tomorrow: [Priority], now: Date = Date()) {
        let todayKey = DayPlanner.workingDay(now: now, plans: data.dayPlans)
        let current = plan(for: todayKey)?.priorities ?? []
        let alreadyDone = Set(current.filter(\.isDone).map(\.id))
        let today = DayPlanner.mergeWrapUp(snapshot: snapshot, into: current)
        updatePlan(day: todayKey) { plan in
            plan.priorities = today
            plan.wrappedUp = true
        }
        let kept = DayPlanner.carryLinks(
            into: tomorrow.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }, from: today)
        // Both writes merge with the stored plans, so a Google-synced priority is never removed (no task deletes).
        let nextKey = DayKey.next(todayKey)
        if nextKey == DayKey.key(for: Date()) {
            // Finishing yesterday after 4 AM: the next day is the live, synced plan, so add to it, never replace.
            updatePlan(day: nextKey) { $0.priorities = DayPlanner.appendNew(kept, to: $0.priorities) }
        } else {
            updatePlan(day: nextKey) { $0.priorities = kept }
        }
        let summary = DaySummary.summarize(day: todayKey, sessions: data.sessions, priorities: today)
        for priority in today where priority.isDone && !alreadyDone.contains(priority.id) {
            postPriorityUpdate(priority)
        }
        announcer.announce(DiscordMessages.dayRecap(
            name: displayName,
            done: today.filter(\.isDone).map(\.title),
            notDone: today.filter { !$0.isDone }.map(\.title),
            tomorrow: kept.map(\.title),
            summary: summary))
        isWrappingUpDay = false
        checkMorning(now: now)
    }

    /// Posts the same Discord recap as wrapping up, using today's ticks and tomorrow's saved priorities.
    func postDayRecap(now: Date = Date()) {
        let current = todayPlan(now: now)
        let tomorrow = plan(for: DayKey.next(current.day))?.priorities ?? []
        wrapUpDay(today: current.priorities, tomorrow: tomorrow, now: now)
    }

    /// The display name from Settings, else the macOS user name.
    var displayName: String {
        let trimmed = data.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSFullUserName() : trimmed
    }

    // MARK: Settings

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&data.settings)
        save()
        syncAutoLaunchAndGuardian()
        VoiceOutput.shared.voice = data.settings.kokoroVoice
        VoiceOutput.shared.volume = Float(data.settings.voiceVolume)
    }

    /// Synchronizes LaunchAgents with user preferences to prevent morning evasion.
    func syncAutoLaunchAndGuardian() {
        AutoLaunchManager.setAutoLaunch(enabled: data.settings.autoLaunchAtLogin)
        AutoLaunchManager.setDayGuardian(enabled: data.settings.dayGuardianEnabled)
    }

    /// Writes `data` to the store. A failure is shown as a toast; the in-memory data stays intact.
    func save() {
        do {
            try store.save(data)
        } catch {
            NSLog("Tofu: saving failed: %@", error.localizedDescription)
            ToastCenter.shared.show("Couldn't save your data: \(error.localizedDescription)")
        }
    }

    /// Key of the team's bot token in the bundled `.env`.
    static let envTokenKey = "DISCORD_BOT_TOKEN"

    /// Picks the bot token: a non-empty Keychain token wins, else the team token from `.env`.
    /// Blank strings count as missing, and the winner is trimmed.
    nonisolated static func resolveToken(keychain: String?, env: String?) -> (token: String?, source: TokenSource) {
        func cleaned(_ raw: String?) -> String? {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let token = cleaned(keychain) { return (token, .keychain) }
        if let token = cleaned(env) { return (token, .teamFile) }
        return (nil, .none)
    }

    private var resolvedToken: (token: String?, source: TokenSource) {
        Self.resolveToken(keychain: keychainToken(), env: envToken())
    }

    /// The Discord bot token in use: the Keychain token, else the team token. Never stored in store.json.
    var discordToken: String? { resolvedToken.token }

    /// Which of the two tokens `discordToken` is.
    var discordTokenSource: TokenSource { resolvedToken.source }

    /// Saves a trimmed token to the Keychain (it then overrides the team token); nil or blank deletes it.
    func setDiscordToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Secrets.discordService, account: Secrets.discordAccount)
        } else {
            Keychain.set(trimmed, service: Secrets.discordService, account: Secrets.discordAccount)
        }
    }

    /// Key of the OpenAI API key in the bundled `.env`.
    static let envOpenAIKeyName = "OPENAI_API_KEY"

    private var resolvedOpenAIKey: (token: String?, source: TokenSource) {
        Self.resolveToken(keychain: keychainOpenAIKey(), env: envOpenAIKey())
    }

    /// The OpenAI key used for the relevance check: the Keychain key, else the team key from `.env`.
    /// Never stored in store.json. Without one every check gives no verdict and the user is asked instead.
    var openAIKey: String? { resolvedOpenAIKey.token }

    /// Which of the two keys `openAIKey` is.
    var openAIKeySource: TokenSource { resolvedOpenAIKey.source }

    /// Saves a trimmed key to the Keychain (it then overrides the team key); nil or blank deletes it.
    func setOpenAIKey(_ key: String?) {
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Secrets.openAIService, account: Secrets.openAIAccount)
        } else {
            Keychain.set(trimmed, service: Secrets.openAIService, account: Secrets.openAIAccount)
        }
    }

    // MARK: Demo data

    /// Adds CS128 and MATH241 when there are no subjects, then (re)seeds about 30 days of demo sessions.
    /// Earlier demo sessions are replaced, so loading twice never duplicates them.
    func loadDemoData() {
        let now = Date()
        if data.subjects.isEmpty {
            data.subjects = DemoData.defaultSubjects(now: now)
            if selection == nil {
                selection = data.subjects.first.map { SidebarItem.subject($0.id) }
            }
        }
        data.sessions.removeAll { $0.isDemo }
        data.sessions.append(contentsOf: DemoData.generate(subjects: data.subjects, now: now))
        save()
    }

    /// Removes every demo session. Subjects and real sessions are kept.
    func clearDemoData() {
        data.sessions.removeAll { $0.isDemo }
        save()
    }
}

/// Posts nowhere (tests that don't care about Discord).
@MainActor private final class SilentAnnouncer: Announcing {
    func announce(_ content: String) {}
}

/// Weak link from the live DiscordAnnouncer's closures back to the model (see `AppModel.init(store:)`).
@MainActor private final class ModelBox {
    weak var model: AppModel?
}

/// How the browser consent step ended: a code with its state, a denial, or no answer in time.
private enum ConnectOutcome {
    case code(String, String)
    case denied
    case timedOut
}

/// Hands one outcome to a single waiter; later fulfills are ignored.
@MainActor private final class CallbackGate {
    private var result: ConnectOutcome?
    private var continuation: CheckedContinuation<ConnectOutcome, Never>?

    func fulfill(_ value: ConnectOutcome) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    func wait() async -> ConnectOutcome {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
}
