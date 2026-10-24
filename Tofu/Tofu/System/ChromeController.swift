import AppKit
import os

/// One browser window to open at lock-in: its websites (the first is shown, the rest are extra tabs) and where
/// it goes (nil = wherever the browser puts it).
struct BrowserWindowPlan: Equatable {
    var urls: [String]
    var bounds: ChromeBounds?
}

@MainActor protocol ChromeControlling: AnyObject {
    /// Called with the closed tab's host (or URL if no host) after each auto-closed tab.
    var onTabClosed: ((String) -> Void)? { get set }
    /// Launch/activate `browser`, remember and close its existing windows (Arc: its unpinned tabs too), then open
    /// one window per plan (URLs normalized with DomainMatcher.normalizedURL; unparseable ones skipped, and a plan
    /// left with none is skipped). The tab watch and the reopening at the end then work on this browser.
    /// A window that still fails after retries (profileNotReady / scriptFailed) does not stop the others from opening.
    /// Returns nil when every window opened, otherwise the first error; notInstalled / automationDenied abort at once.
    func prepare(browser: Browser, windows: [BrowserWindowPlan]) async -> ChromeError?
    /// Starts the 2 s tab poll. Every tab outside `studySites` is judged for relevance to `subject` (the subject's
    /// name, e.g. "CS128", described by `details`, which may be empty) and closed when it is off-task.
    /// Replaces any watch already running.
    func startTabWatch(subject: String, details: String, studySites: [String])
    /// Stops polling for a break. Allow and close decisions made while paused still apply when the watch resumes.
    func pauseTabWatch()
    /// Closes every open tab that is not a study site or a host allowed during this block.
    func closeUnrelatedTabs()
    func stopTabWatch()
    /// Opens again the windows `prepare` closed and the tabs the watch closed.
    func restoreAfterSession()
    /// Hands back what `prepare` and the tab watch closed, and forgets it. Nothing is reopened.
    func takeClosedBrowser() -> ClosedBrowserState?
    /// Opens these pages again in the session's browser (already-open ones are skipped).
    func reopen(urls: [String])
    /// Called when a host is allowed for the session (the assistant, or the user answering "Needed").
    var onHostAllowed: ((String) -> Void)? { get set }
}

/// Drives Google Chrome and Arc with NSAppleScript. Never scripts System Events.
/// The repeating tab poll runs the script off the main thread so dragging the timer and typing in chat stay responsive.
/// One script runs at a time; a call that is already on the main thread still runs there so it cannot deadlock
/// waiting for a script that needs this process's run loop.
/// While the tab watch runs, each new tab URL is judged by a `RelevanceJudging`; off-task tabs are closed by tab id.
/// When no verdict can be had, the chat popup asks about the host. The alert prompt is not used.
/// Pages that are only maybe relevant (`.unsure`) go to the chat assistant (`SiteAsking`), which answers later
/// through `SiteVerdictReceiving` (`allowHost` / `closeHost`).
@MainActor final class ChromeController: ChromeControlling, SiteVerdictReceiving {
    /// AppleScript error number for "Not authorized to send Apple events" (Automation denied).
    static let automationDeniedErrorNumber = -1743
    static let tabPollInterval: TimeInterval = 2
    /// Front-space polls between readings of Arc's other spaces. 30 × 2 s is about a minute.
    static let arcFullSweepEvery = 30
    static let openRetries = 3
    static let launchTimeout: TimeInterval = 5

    var onTabClosed: ((String) -> Void)?
    var onHostAllowed: ((String) -> Void)?
    /// The chat assistant that gets the unsure sites. Weak: AppModel owns both ends.
    weak var asker: SiteAsking?
    /// The browser of the latest `prepare` (Chrome until then).
    private(set) var browser: Browser = .chrome
    /// Front-space polls since the last reading of Arc's other spaces. The next poll is that reading at `arcFullSweepEvery`.
    private var pollsSinceFullSweep = 0
    /// What to open again at the end; mirrored to `rememberedURL` on every change.
    private(set) var remembered: ClosedBrowserState?
    private let rememberedURL: URL?
    private var tabTimer: Timer?
    /// True while a tab-list script is running off the main thread. A second poll waits for it.
    private var pollInFlight = false
    /// Bumped when the watch stops so a script that returns late is discarded.
    private var pollGeneration = 0
    /// Production polls leave the main thread. Tests that inject `runScript` stay synchronous unless they opt in.
    private let pollsOffMainThread: Bool

    private let judge: RelevanceJudging
    /// Domains closed without asking the judge (`DistractionList.hosts` in the app).
    private let alwaysBlocked: [String]
    /// Runs an AppleScript source; tests replace it so no real Chrome is needed.
    private let runScript: (String) -> Result<String, ChromeError>
    /// True when scripts may be sent (a browser process exists); tests replace it. nil = the real check.
    private let browserIsRunningOverride: (() -> Bool)?
    /// Moves the browser's front window to bounds, for browsers whose windows take no `bounds` (Arc).
    private let placeFrontWindow: (Browser, ChromeBounds) async -> Void

    /// The subject's name from the latest `startTabWatch`, e.g. "CS128".
    private(set) var subjectName = ""
    /// The subject's description from the latest `startTabWatch`, passed to the judge with the name.
    private var subjectDetails = ""
    private var triage = TabTriage(studySites: [], protected: [])
    /// Tabs seen by the latest poll (minus the ones closed since), for `openTabsSummary`.
    private var lastTabs: [ChromeTab] = []
    /// Changes on every start/stop of the watch, so verdicts and answers that arrive late are ignored.
    private var watchToken = UUID()
    /// Allow / close decisions for this lock-in, including ones made while the watch is paused for a break.
    /// The next `startTabWatch` applies them. Stopping the watch, or preparing the next lock-in, clears them.
    private var sessionAnswers: [String: Bool] = [:]
    /// True from the first `startTabWatch` of a lock-in until `stopTabWatch`. A decision before that, or after the
    /// session's watch has ended, is ignored.
    private var acceptsSiteDecisions = false
    /// Hosts handed to the assistant this watch: a host is asked about at most once.
    private var askedAssistantHosts: Set<String> = []

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) != nil
    }

    /// `runScript` and `chromeIsRunning` exist for tests (nil = the real browser via NSAppleScript).
    /// `rememberedURL` is where closed windows and tabs are kept until reopened (nil = memory only); a state left
    /// there by a crash is loaded and reopened by the next `restoreAfterSession`.
    init(judge: RelevanceJudging, alwaysBlocked: [String] = [],
         rememberedURL: URL? = nil, browser: Browser = .chrome,
         runScript: ((String) -> Result<String, ChromeError>)? = nil,
         chromeIsRunning: (() -> Bool)? = nil,
         pollsOffMainThread: Bool? = nil,
         placeFrontWindow: ((Browser, ChromeBounds) async -> Void)? = nil) {
        self.judge = judge
        self.alwaysBlocked = alwaysBlocked
        self.rememberedURL = rememberedURL
        self.browser = browser
        self.remembered = ClosedBrowserState.load(from: rememberedURL)
        self.runScript = runScript ?? { ChromeController.run($0) }
        self.pollsOffMainThread = pollsOffMainThread ?? (runScript == nil)
        self.browserIsRunningOverride = chromeIsRunning
        self.placeFrontWindow = placeFrontWindow ?? { browser, bounds in
            _ = await WindowPlacer.place(bundleID: browser.bundleID, bounds: bounds)
        }
    }

    /// True when a process of `browser` exists. Scripts are only sent while this is true (except during prepare and
    /// requestAccess), because any `tell application` would relaunch a browser that was quit.
    static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    private func chromeIsRunning() -> Bool {
        browserIsRunningOverride?() ?? Self.isRunning(browser)
    }

    /// Only one AppleScript runs at a time. NSAppleScript is not safe to call concurrently.
    private static let scriptLock = NSLock()

    /// Compiles and runs `source`. Error -1743 maps to .automationDenied, every other error to .scriptFailed(message).
    /// Safe to call off the main thread. Callers share one lock so two scripts never run at once.
    nonisolated static func run(_ source: String) -> Result<String, ChromeError> {
        scriptLock.lock()
        defer { scriptLock.unlock() }
        return execute(source)
    }

    nonisolated private static func execute(_ source: String) -> Result<String, ChromeError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("Could not create AppleScript"))
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if number == automationDeniedErrorNumber { return .failure(.automationDenied) }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
            return .failure(.scriptFailed(message))
        }
        return .success(output.stringValue ?? "")
    }

    func prepare(browser: Browser, windows: [BrowserWindowPlan]) async -> ChromeError? {
        sessionAnswers = [:]
        self.browser = browser
        pollsSinceFullSweep = 0
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return .notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            Log.browser.error("Couldn't launch \(browser.bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        var waited: TimeInterval = 0
        while !Self.isRunning(browser) && waited < Self.launchTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }

        let snapshot: ChromeScripts.ArcListing = browser == .arc ? .everySpace : .frontSpace
        switch Self.run(ChromeScripts.listTabs(for: browser, arcListing: snapshot)) {
        case .success(let output):
            closeExistingWindows(ChromeScripts.parseTabs(output, browser: browser))
        case .failure(.automationDenied):
            Log.browser.error("Automation permission denied for \(browser.bundleID, privacy: .public)")
            return .automationDenied
        case .failure(let error):
            Log.browser.error("Listing tabs before lock-in failed: \(String(describing: error), privacy: .public)")
            // not fatal: nothing is closed (it could not be remembered), the new windows open on top
        }

        let plans = Self.openingPlans(browser: browser, windows: windows).map { window in
            (script: ChromeScripts.openWindow(urls: window.urls, bounds: window.bounds, browser: browser),
             bounds: window.bounds)
        }
        return await Self.openAll(plans) { plan in
            let error = await openWithRetry(plan.script)
            if error == nil, let bounds = plan.bounds, !browser.supportsBounds { await placeFrontWindow(browser, bounds) }
            return error
        }
    }

    /// The windows to actually open. URLs are normalized ("cs128.org" -> "https://cs128.org") and de-duplicated.
    /// Arc shows the same tabs in every window of a space, so every website goes in one window; opening a second
    /// would create another copy of each tab.
    nonisolated static func openingPlans(browser: Browser, windows: [BrowserWindowPlan]) -> [BrowserWindowPlan] {
        func normalized(_ urls: [String]) -> [String] {
            var seen = Set<String>()
            return urls.compactMap { DomainMatcher.normalizedURL($0)?.absoluteString }.filter { seen.insert($0).inserted }
        }
        if browser == .arc {
            var seen = Set<String>()
            var urls: [String] = []
            var bounds: ChromeBounds?
            for window in windows {
                if bounds == nil { bounds = window.bounds }
                for url in normalized(window.urls) where seen.insert(url).inserted { urls.append(url) }
            }
            return urls.isEmpty ? [] : [BrowserWindowPlan(urls: urls, bounds: bounds)]
        }
        return windows.compactMap { window in
            let urls = normalized(window.urls)
            return urls.isEmpty ? nil : BrowserWindowPlan(urls: urls, bounds: window.bounds)
        }
    }

    /// Opens every window in order. automationDenied / notInstalled stop immediately; any other error is
    /// remembered and the remaining sites are still attempted. Returns the first error, or nil if none failed.
    static func openAll<Window>(_ windows: [Window], using open: (Window) async -> ChromeError?) async -> ChromeError? {
        var firstError: ChromeError?
        for window in windows {
            guard let error = await open(window) else { continue }
            switch error {
            case .automationDenied, .notInstalled: return error
            case .profileNotReady, .scriptFailed: firstError = firstError ?? error
            }
        }
        return firstError
    }

    /// Remembers the open windows (saved to disk first, so nothing is lost if the app dies right after), then
    /// closes them. In Arc a closed window's tabs stay in the sidebar, so its unpinned tabs are closed as well;
    /// pinned tabs are never listed, so they stay.
    private func closeExistingWindows(_ tabs: [ChromeTab]) {
        let windows = ClosedBrowserState.windows(from: tabs, browser: browser)
        var state = ClosedBrowserState(browser: browser, windows: windows, closedTabs: [])
        for tab in tabs { state.recordTitle(tab.title, for: tab.url) }
        if var existing = remembered, existing.browser == browser {
            existing.merge(state)
            remember(existing)
        } else {
            if let other = remembered { reopen(other) }   // a different browser's leftovers: give them back first
            remember(state)
        }
        if browser == .arc { _ = Self.run(ChromeScripts.closeTabs(tabs, browser: .arc)) }
        _ = Self.run(ChromeScripts.closeAllWindows(for: browser))
    }

    private func remember(_ state: ClosedBrowserState?) {
        remembered = state
        ClosedBrowserState.save(state, to: rememberedURL)
    }

    /// First attempt plus `openRetries` retries, 1 s apart. `make new window` fails until a profile is loaded.
    private func openWithRetry(_ script: String) async -> ChromeError? {
        for attempt in 0...Self.openRetries {
            switch Self.run(script) {
            case .success: return nil
            case .failure(.automationDenied): return .automationDenied
            case .failure:
                if attempt < Self.openRetries { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        return .profileNotReady
    }

    func startTabWatch(subject: String, details: String = "", studySites: [String]) {
        haltPolling()
        acceptsSiteDecisions = true
        subjectName = subject
        subjectDetails = details
        triage = TabTriage(studySites: studySites, protected: [], alwaysBlocked: alwaysBlocked)
        for (host, needed) in sessionAnswers {
            triage.recordAnswer(host: host, needed: needed)
        }
        let timer = Timer(timeInterval: Self.tabPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTabs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabTimer = timer
        pollsSinceFullSweep = 0
        pollTabs()
    }

    func pauseTabWatch() {
        haltPolling()
    }

    func closeUnrelatedTabs() {
        guard chromeIsRunning(), case .success(let output) = listTabsNow(arcListing: .everySpace) else { return }
        let tabs = ChromeScripts.parseTabs(output, browser: browser)
        lastTabs = tabs
        for tab in tabs where !triage.isRelated(tab) {
            close(tab)
        }
    }

    /// Stops polling and forgets this lock-in's site decisions. Verdicts still on their way are ignored.
    func stopTabWatch() {
        acceptsSiteDecisions = false
        sessionAnswers = [:]
        haltPolling()
    }

    /// Stops the poll and forgets which hosts were asked about, without forgetting allow / close decisions.
    private func haltPolling() {
        tabTimer?.invalidate()
        tabTimer = nil
        watchToken = UUID()
        pollGeneration += 1
        pollInFlight = false
        askedAssistantHosts = []
        lastTabs = []
    }

    /// One poll: list every tab, close the ones already known to be off-task (by tab id), and start a relevance
    /// check for every tab that needs a verdict.
    /// Internal (not private) so tests can drive it without the timer.
    /// The repeating watch runs the list script off the main thread. The timer only starts that work, so a slow
    /// Arc listing cannot freeze a drag or a keystroke. Tests inject a script runner and stay synchronous.
    func pollTabs() {
        guard chromeIsRunning() else { return }
        guard pollsOffMainThread else {
            applyPoll(listTabsNow(arcListing: nextArcListing()))
            return
        }
        guard !pollInFlight else { return }
        pollInFlight = true
        let generation = pollGeneration
        let token = watchToken
        let source = ChromeScripts.listTabs(for: browser, arcListing: nextArcListing())
        let run = runScript
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = run(source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.pollGeneration == generation else { return }
                    self.pollInFlight = false
                    guard self.watchToken == token else { return }
                    self.applyPoll(result)
                }
            }
        }
    }

    /// The space on screen, until `arcFullSweepEvery` polls have run. Then every space, once.
    private func nextArcListing() -> ChromeScripts.ArcListing {
        guard browser == .arc else { return .frontSpace }
        pollsSinceFullSweep += 1
        if pollsSinceFullSweep >= Self.arcFullSweepEvery {
            pollsSinceFullSweep = 0
            return .everySpace
        }
        return .frontSpace
    }

    /// Applies a finished tab listing.
    private func applyPoll(_ result: Result<String, ChromeError>) {
        switch result {
        case .success(let output):
            let tabs = ChromeScripts.parseTabs(output, browser: browser)
            lastTabs = tabs
            closeKnownOffTask(in: tabs)
            for tab in triage.tabsToCheck(tabs) {
                check(tab)
            }
        case .failure(.automationDenied):
            Log.browser.error("Automation permission revoked; tab watch stopped")
            stopTabWatch()   // permission revoked mid-session: stop retrying every 2 s
        case .failure(let error):
            // Chrome busy or quitting; try again next tick
            Log.browser.debug("Tab poll failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The current tab list. `.everySpace` is for a close that has to see tabs that are not on screen.
    private func listTabsNow(arcListing: ChromeScripts.ArcListing = .frontSpace) -> Result<String, ChromeError> {
        let listing: ChromeScripts.ArcListing = browser == .arc ? arcListing : .frontSpace
        return runScript(ChromeScripts.listTabs(for: browser, arcListing: listing))
    }

    /// Closes every tab of `tabs` that is already known to be off-task (see `TabTriage.shouldCloseImmediately`).
    private func closeKnownOffTask(in tabs: [ChromeTab]) {
        for tab in tabs where triage.shouldCloseImmediately(tab) {
            close(tab)
        }
    }

    /// Closes the tab by its id and reports its host. False when the script failed.
    @discardableResult
    private func close(_ tab: ChromeTab) -> Bool {
        if case .failure(let error) = runScript(ChromeScripts.closeTab(windowID: tab.windowID, tabID: tab.tabID, browser: browser)) {
            Log.browser.error("Closing tab failed: \(String(describing: error), privacy: .public)")
            return false
        }
        lastTabs.removeAll { $0.windowID == tab.windowID && $0.tabID == tab.tabID }
        if ClosedBrowserState.isReopenable(tab.url) {
            var state = remembered ?? ClosedBrowserState(browser: browser, windows: [], closedTabs: [])
            state.closedTabs.append(tab.url)
            state.recordTitle(tab.title, for: tab.url)
            remember(state)
        }
        onTabClosed?(DomainMatcher.host(of: tab.url) ?? tab.url)
        return true
    }

    /// Closes the tab only if it is still open at the same address, so a tab the user already closed (or sent
    /// elsewhere) while the verdict was pending is neither counted nor touched.
    private func closeIfStillOpen(_ tab: ChromeTab) {
        guard chromeIsRunning(), case .success(let output) = listTabsNow(arcListing: .everySpace) else { return }
        // Arc tab ids are unique across windows; the window a tab was listed under can change between polls.
        guard let current = ChromeScripts.parseTabs(output, browser: browser).first(where: { listed in
            let sameTab = browser.hasTextTabIDs ? listed.tabID == tab.tabID
                : listed.windowID == tab.windowID && listed.tabID == tab.tabID
            return sameTab && listed.url == tab.url
        }) else { return }
        close(current)
    }

    /// Asks the judge about one tab without blocking the poll. The result is ignored if the watch was stopped
    /// or restarted meanwhile.
    private func check(_ tab: ChromeTab) {
        let token = watchToken
        let subject = subjectName
        let details = subjectDetails
        let judge = judge
        let page = PageInfo(url: tab.url, title: tab.title, description: nil, siteName: nil)
        Task { @MainActor [weak self] in
            let verdict = await judge.judge(page: page, subject: subject, details: details)
            self?.handle(verdict, for: tab, token: token)
        }
    }

    private func handle(_ verdict: RelevanceVerdict, for tab: ChromeTab, token: UUID) {
        guard token == watchToken else { return }
        Log.relevance.info("Verdict \(String(describing: verdict), privacy: .public) for \(tab.url)")
        triage.record(url: tab.url, verdict: verdict)
        switch verdict {
        case .relevant:
            break
        case .offTask:
            // The user may have answered "Needed" for this host while the check was running.
            if triage.shouldCloseImmediately(tab) { closeIfStillOpen(tab) }
        case .unknown:
            // Same popup as an unsure site. A negative relevance means the check itself failed.
            if !triage.isHostAnswered(tab) { askAssistant(about: tab, relevance: -1) }
        case .unsure(let relevance):
            // The tab stays open. Unless the chat already settled this host while the check ran, the assistant asks.
            if !triage.isHostAnswered(tab) { askAssistant(about: tab, relevance: relevance) }
        }
    }

    /// Hands the tab's host to the chat assistant; each host is asked about at most once per watch.
    private func askAssistant(about tab: ChromeTab, relevance: Double) {
        let host = DomainMatcher.host(of: tab.url) ?? tab.url
        guard askedAssistantHosts.insert(host).inserted else { return }
        asker?.askAboutSite(SiteQuestion(host: host, url: tab.url, title: tab.title, relevance: relevance),
                            subject: subjectName)
    }

    // MARK: SiteVerdictReceiving

    /// The assistant allowed the site: every tab on `host` stays for the rest of the watch.
    func allowHost(_ host: String) {
        let host = DomainMatcher.normalize(host)
        guard acceptsSiteDecisions, !host.isEmpty else { return }
        sessionAnswers[host] = true
        triage.allowHost(host)
        onHostAllowed?(host)
    }

    /// The assistant closed the site: every open tab on `host` is closed now (from a fresh tab list, so a tab the
    /// user already closed is not counted), and the host is closed on every later poll too.
    func closeHost(_ host: String) {
        let host = DomainMatcher.normalize(host)
        guard acceptsSiteDecisions, !host.isEmpty else { return }
        sessionAnswers[host] = false
        triage.closeHost(host)
        guard tabTimer != nil, chromeIsRunning(), case .success(let output) = listTabsNow(arcListing: .everySpace) else { return }
        let tabs = ChromeScripts.parseTabs(output, browser: browser)
        lastTabs = tabs
        closeKnownOffTask(in: tabs)
    }

    /// One "host — title" line per tab of the latest poll (just the host when the title is blank).
    var openTabsSummary: [String] {
        lastTabs.map { tab in
            let host = DomainMatcher.host(of: tab.url) ?? tab.url
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? host : "\(host) — \(title)"
        }
    }

    /// Opens again the windows `prepare` closed and the tabs the watch closed (also what a crash left on disk),
    /// skipping pages that are already open, then forgets them.
    func restoreAfterSession() {
        guard let state = remembered else { return }
        remember(nil)
        reopen(state)
    }

    func takeClosedBrowser() -> ClosedBrowserState? {
        guard let state = remembered, !state.isEmpty else {
            remember(nil)
            return nil
        }
        remember(nil)
        return state
    }

    func reopen(urls: [String]) {
        let state = ClosedBrowserState(browser: browser, windows: [], closedTabs: urls)
        reopen(state)
    }

    private func reopen(_ state: ClosedBrowserState) {
        guard !state.isEmpty else { return }
        var open = Set<String>()
        let listing: ChromeScripts.ArcListing = state.browser == .arc ? .everySpace : .frontSpace
        if browserIsRunningOverride?() ?? Self.isRunning(state.browser),
           case .success(let output) = runScript(ChromeScripts.listTabs(for: state.browser, arcListing: listing)) {
            open = Set(ChromeScripts.parseTabs(output, browser: state.browser).map(\.url))
        }
        for urls in state.windowsToReopen(alreadyOpen: open) {
            let script = state.browser == .arc
                ? ChromeScripts.openTabs(urls: urls)
                : ChromeScripts.openWindow(urls: urls, bounds: nil, browser: state.browser)
            _ = runScript(script)
        }
    }

    /// True when a crash left closed windows or tabs that were never reopened.
    var hasLeftovers: Bool { !(remembered?.isEmpty ?? true) }

    /// Runs ChromeScripts.ping (launching Chrome if needed) to trigger the Automation prompt.
    static func requestAccess() -> ChromeError? {
        guard Self.isInstalled else { return .notInstalled }
        switch Self.run(ChromeScripts.ping) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
