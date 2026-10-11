import AppKit

@MainActor protocol ChromeControlling: AnyObject {
    /// Called with the closed tab's host (or URL if no host) after each auto-closed tab.
    var onTabClosed: ((String) -> Void)? { get set }
    /// Launch/activate Chrome, minimize existing windows, open one window per site (sites normalized with
    /// DomainMatcher.normalizedURL; unparseable sites skipped). bounds[i] applies to sites[i]; when bounds is
    /// shorter than sites (e.g. no screen), windows without a matching bounds entry are opened without setting bounds.
    /// A site that still fails after retries (profileNotReady / scriptFailed) does not stop the others from opening.
    /// Returns nil when every site opened, otherwise the first error; notInstalled / automationDenied abort at once.
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError?
    /// Starts the 2 s tab poll. Every tab outside `studySites` is judged for relevance to `subject` (the subject's
    /// name, e.g. "CS128") and closed when it is off-task. Replaces any watch already running.
    func startTabWatch(subject: String, studySites: [String])
    func stopTabWatch()
    func restoreMinimized()
}

/// Drives Google Chrome with NSAppleScript (main thread). Never scripts System Events.
/// While the tab watch runs, each new tab URL is judged by a `RelevanceJudging`; off-task tabs are closed by tab id.
/// When no verdict can be had, the user is asked about the host, one question at a time (`NeedPrompting`).
@MainActor final class ChromeController: ChromeControlling {
    /// AppleScript error number for "Not authorized to send Apple events" (Automation denied).
    static let automationDeniedErrorNumber = -1743
    static let tabPollInterval: TimeInterval = 2
    static let openRetries = 3
    static let launchTimeout: TimeInterval = 5

    var onTabClosed: ((String) -> Void)?
    private var minimizedIDs: [Int] = []
    /// Protection keys of the tabs that existed before `prepare` opened the study windows. The tab watch never
    /// closes them, so the user's own windows (minimized at lock-in, restored at the end) keep their tabs.
    private var preexistingTabs: Set<String> = []
    /// Ids of the windows that existed before `prepare`. The tab watch re-minimizes them whenever the user
    /// un-minimizes one, so their protected tabs cannot be used as a way around the relevance check.
    private var preexistingWindowIDs: Set<Int> = []
    private var tabTimer: Timer?

    private let judge: RelevanceJudging
    private let prompter: NeedPrompting
    /// Runs an AppleScript source; tests replace it so no real Chrome is needed.
    private let runScript: (String) -> Result<String, ChromeError>
    /// True when scripts may be sent (a Chrome process exists); tests replace it.
    private let chromeIsRunning: () -> Bool

    private var subject = ""
    private var triage = TabTriage(studySites: [], protected: [])
    /// Changes on every start/stop of the watch, so verdicts and answers that arrive late are ignored.
    private var watchToken = UUID()
    /// Hosts waiting for their "Is it needed?" question, oldest first; only one question is on screen at a time.
    private var promptQueue: [String] = []
    /// Hosts that were queued or asked this watch: a host is asked at most once.
    private var promptedHosts: Set<String> = []
    private var isPrompting = false

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) != nil
    }

    /// True when a Chrome process exists. Scripts are only sent while this is true (except during prepare and
    /// requestAccess), because any `tell application "Google Chrome"` would relaunch a quit Chrome.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeScripts.bundleID).isEmpty
    }

    /// `runScript` and `chromeIsRunning` exist for tests (nil = the real Chrome via NSAppleScript).
    init(judge: RelevanceJudging, prompter: NeedPrompting,
         runScript: ((String) -> Result<String, ChromeError>)? = nil,
         chromeIsRunning: (() -> Bool)? = nil) {
        self.judge = judge
        self.prompter = prompter
        self.runScript = runScript ?? { ChromeController.run($0) }
        self.chromeIsRunning = chromeIsRunning ?? { ChromeController.isRunning }
    }

    /// Compiles and runs `source`. Error -1743 maps to .automationDenied, every other error to .scriptFailed(message).
    static func run(_ source: String) -> Result<String, ChromeError> {
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

    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) else {
            return .notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        var waited: TimeInterval = 0
        while !Self.isRunning && waited < Self.launchTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }

        switch Self.run(ChromeScripts.minimizeAll) {
        case .success(let output): minimizedIDs = ChromeScripts.parseIDs(output)
        case .failure(.automationDenied): return .automationDenied
        case .failure: minimizedIDs = []   // not fatal: the new windows still open on top
        }
        if case .success(let output) = Self.run(ChromeScripts.listTabs) {
            let tabs = ChromeScripts.parseTabs(output)
            preexistingTabs = Set(tabs.map(ChromeScripts.protectionKey))
            preexistingWindowIDs = Set(tabs.map(\.windowID))
        } else {
            preexistingTabs = []
            preexistingWindowIDs = []
        }
        preexistingWindowIDs.formUnion(minimizedIDs)

        var scripts: [String] = []
        for (index, site) in sites.enumerated() {
            guard let url = DomainMatcher.normalizedURL(site) else { continue }
            scripts.append(index < bounds.count
                ? ChromeScripts.openWindow(url: url.absoluteString, bounds: bounds[index])
                : ChromeScripts.openWindow(url: url.absoluteString))
        }
        return await Self.openAll(scripts) { await self.openWithRetry($0) }
    }

    /// Opens every script's window in order. automationDenied / notInstalled stop immediately; any other error is
    /// remembered and the remaining sites are still attempted. Returns the first error, or nil if none failed.
    static func openAll(_ scripts: [String], using open: (String) async -> ChromeError?) async -> ChromeError? {
        var firstError: ChromeError?
        for script in scripts {
            guard let error = await open(script) else { continue }
            switch error {
            case .automationDenied, .notInstalled: return error
            case .profileNotReady, .scriptFailed: firstError = firstError ?? error
            }
        }
        return firstError
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

    func startTabWatch(subject: String, studySites: [String]) {
        stopTabWatch()
        self.subject = subject
        triage = TabTriage(studySites: studySites, protected: preexistingTabs)
        let timer = Timer(timeInterval: Self.tabPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTabs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabTimer = timer
    }

    /// Stops polling and forgets queued questions. Verdicts and answers still on their way are ignored.
    func stopTabWatch() {
        tabTimer?.invalidate()
        tabTimer = nil
        watchToken = UUID()
        promptQueue = []
        promptedHosts = []
        isPrompting = false
    }

    /// One poll: list every tab, close the ones already known to be off-task (by tab id), start a relevance check
    /// for every tab that needs a verdict, then minimize again any pre-existing window the user brought back.
    /// Internal (not private) so tests can drive it without the timer.
    func pollTabs() {
        guard chromeIsRunning() else { return }
        switch runScript(ChromeScripts.listTabs) {
        case .success(let output):
            let tabs = ChromeScripts.parseTabs(output)
            for tab in tabs where triage.shouldCloseImmediately(tab) {
                close(tab)
            }
            for tab in triage.tabsToCheck(tabs) {
                check(tab)
            }
            let liveWindowIDs = Set(tabs.map(\.windowID))
            let strays = preexistingWindowIDs.filter(liveWindowIDs.contains).sorted()
            if !strays.isEmpty { _ = runScript(ChromeScripts.minimize(windowIDs: strays)) }
        case .failure(.automationDenied):
            stopTabWatch()   // permission revoked mid-session: stop retrying every 2 s
        case .failure:
            break            // Chrome busy or quitting; try again next tick
        }
    }

    /// Closes the tab by its id and reports its host. False when the script failed.
    @discardableResult
    private func close(_ tab: ChromeTab) -> Bool {
        guard case .success = runScript(ChromeScripts.closeTab(windowID: tab.windowID, tabID: tab.tabID)) else {
            return false
        }
        onTabClosed?(DomainMatcher.host(of: tab.url) ?? tab.url)
        return true
    }

    /// Closes the tab only if it is still open at the same address, so a tab the user already closed (or sent
    /// elsewhere) while the verdict was pending is neither counted nor touched.
    private func closeIfStillOpen(_ tab: ChromeTab) {
        guard chromeIsRunning(), case .success(let output) = runScript(ChromeScripts.listTabs) else { return }
        let isOpen = ChromeScripts.parseTabs(output).contains {
            $0.windowID == tab.windowID && $0.tabID == tab.tabID && $0.url == tab.url
        }
        if isOpen { close(tab) }
    }

    /// Asks the judge about one tab without blocking the poll. The result is ignored if the watch was stopped
    /// or restarted meanwhile.
    private func check(_ tab: ChromeTab) {
        let token = watchToken
        let subject = subject
        let judge = judge
        let page = PageInfo(url: tab.url, title: tab.title, description: nil, siteName: nil)
        Task { @MainActor [weak self] in
            let verdict = await judge.judge(page: page, subject: subject)
            self?.handle(verdict, for: tab, token: token)
        }
    }

    private func handle(_ verdict: RelevanceVerdict, for tab: ChromeTab, token: UUID) {
        guard token == watchToken else { return }
        triage.record(url: tab.url, verdict: verdict)
        switch verdict {
        case .relevant:
            break
        case .offTask:
            // The user may have answered "Needed" for this host while the check was running.
            if triage.shouldCloseImmediately(tab) { closeIfStillOpen(tab) }
        case .unknown:
            askIfNeeded(host: DomainMatcher.host(of: tab.url) ?? tab.url)
        }
    }

    /// Queues the question for `host`; each host is asked at most once per watch.
    private func askIfNeeded(host: String) {
        guard promptedHosts.insert(host).inserted else { return }
        promptQueue.append(host)
        askNext()
    }

    /// Shows the next queued question unless one is already on screen. "Close tab" closes every tab of the host
    /// on the next poll; "Needed" keeps the host for the session.
    private func askNext() {
        guard !isPrompting, !promptQueue.isEmpty else { return }
        isPrompting = true
        let host = promptQueue.removeFirst()
        let token = watchToken
        let subject = subject
        let prompter = prompter
        Task { @MainActor [weak self] in
            let needed = await prompter.askIfNeeded(host: host, subject: subject)
            guard let self, token == self.watchToken else { return }
            self.triage.recordAnswer(host: host, needed: needed)
            self.isPrompting = false
            self.askNext()
        }
    }

    /// Un-minimizes the windows `prepare` minimized, and stops the tab watch from minimizing them again.
    func restoreMinimized() {
        let ids = minimizedIDs
        minimizedIDs = []
        preexistingWindowIDs = []
        guard !ids.isEmpty, Self.isRunning else { return }
        _ = Self.run(ChromeScripts.restore(windowIDs: ids))
    }

    /// Runs ChromeScripts.ping (launching Chrome if needed) to trigger the Automation prompt.
    static func requestAccess() -> ChromeError? {
        guard Self.isInstalled else { return .notInstalled }
        switch Self.run(ChromeScripts.ping) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
