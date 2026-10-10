import AppKit

@MainActor protocol ChromeControlling: AnyObject {
    /// Called with the closed tab's host (or URL if no host) after each auto-closed tab.
    var onTabClosed: ((String) -> Void)? { get set }
    /// Launch/activate Chrome, minimize existing windows, open one window per site (sites normalized with
    /// DomainMatcher.normalizedURL; unparseable sites skipped). bounds[i] applies to sites[i]; when bounds is
    /// shorter than sites (e.g. no screen), windows without a matching bounds entry are opened without setting bounds.
    /// Returns nil on success, otherwise the first fatal error (notInstalled / automationDenied / profileNotReady).
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError?
    func startTabWatch(allowedDomains: [String])
    func stopTabWatch()
    func restoreMinimized()
}

/// Drives Google Chrome with NSAppleScript (main thread). Never scripts System Events.
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
    private var allowedDomains: [String] = []
    private var tabTimer: Timer?

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) != nil
    }

    /// True when a Chrome process exists. Scripts are only sent while this is true (except during prepare and
    /// requestAccess), because any `tell application "Google Chrome"` would relaunch a quit Chrome.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeScripts.bundleID).isEmpty
    }

    init() {}

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
            preexistingTabs = Set(ChromeScripts.parseTabs(output).map(ChromeScripts.protectionKey))
        } else {
            preexistingTabs = []
        }

        for (index, site) in sites.enumerated() {
            guard let url = DomainMatcher.normalizedURL(site) else { continue }
            let script = index < bounds.count
                ? ChromeScripts.openWindow(url: url.absoluteString, bounds: bounds[index])
                : ChromeScripts.openWindow(url: url.absoluteString)
            if let error = await openWithRetry(script) { return error }
        }
        return nil
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

    func startTabWatch(allowedDomains: [String]) {
        stopTabWatch()
        self.allowedDomains = allowedDomains
        let timer = Timer(timeInterval: Self.tabPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTabs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabTimer = timer
    }

    func stopTabWatch() {
        tabTimer?.invalidate()
        tabTimer = nil
    }

    /// One poll: list every tab, close the disallowed ones (descending index per window), report each closed host.
    private func pollTabs() {
        guard Self.isRunning else { return }
        switch Self.run(ChromeScripts.listTabs) {
        case .success(let output):
            let tabs = ChromeScripts.parseTabs(output)
            for tab in ChromeScripts.tabsToClose(tabs, allowedDomains: allowedDomains, protected: preexistingTabs) {
                let script = ChromeScripts.closeTab(windowID: tab.windowID, tabIndex: tab.tabIndex)
                if case .success = Self.run(script) {
                    onTabClosed?(DomainMatcher.host(of: tab.url) ?? tab.url)
                }
            }
        case .failure(.automationDenied):
            stopTabWatch()   // permission revoked mid-session: stop retrying every 2 s
        case .failure:
            break            // Chrome busy or quitting; try again next tick
        }
    }

    func restoreMinimized() {
        let ids = minimizedIDs
        minimizedIDs = []
        guard !ids.isEmpty, Self.isRunning else { return }
        _ = Self.run(ChromeScripts.restore(windowIDs: ids))
    }

    /// Runs ChromeScripts.ping (launching Chrome if needed) to trigger the Automation prompt.
    func requestAccess() -> ChromeError? {
        guard Self.isInstalled else { return .notInstalled }
        switch Self.run(ChromeScripts.ping) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
