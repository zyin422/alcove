import AppKit

@MainActor protocol AppBlocking: AnyObject {
    /// Called once per counted attempt (after debounce). The app has already been quit, or hidden when it must not be quit.
    var onBlocked: ((RunningAppInfo) -> Void)? { get set }
    func start(allowed: Set<String>)
    func stop()
    /// Lets this app stay in front for the rest of the run. A later `start` replaces the set.
    func allow(_ bundleID: String)
    /// Revokes permission for this app during the run, quitting or hiding any currently running instances.
    func revoke(_ bundleID: String)
}

/// Quits disallowed apps the moment they launch or come to the front. Finder and the developer tools are only hidden.
@MainActor final class AppBlocker: AppBlocking {
    /// Seconds after the first hide at which a still-visible app is hidden again
    /// (an app that is still launching can show itself again when its first window appears).
    static let rehideDelays: [TimeInterval] = [0.3, 1.0]

    var onBlocked: ((RunningAppInfo) -> Void)?
    private let fallbackBundleID: String
    private var allowed: Set<String> = []
    private var debouncer = AttemptDebouncer()
    private var observers: [NSObjectProtocol] = []
    private var watchdogTimer: Timer?
    /// Bumped by every start/stop so delayed re-hides from an earlier run do nothing.
    private var generation = 0

    /// After hiding, activates `fallbackBundleID` if it is running, otherwise our own app.
    init(fallbackBundleID: String = "com.google.Chrome") {
        self.fallbackBundleID = fallbackBundleID
    }

    func start(allowed: Set<String>) {
        stop()
        self.allowed = allowed
        debouncer = AttemptDebouncer()
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.handle(pid: pid) }
            }
            observers.append(token)
        }
        sweepRunningApplications()
        startWatchdog()
    }

    func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
        generation += 1
    }

    func allow(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        allowed.insert(bundleID)
    }

    func revoke(_ bundleID: String) {
        guard allowed.remove(bundleID) != nil else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            handle(pid: app.processIdentifier)
        }
    }

    private func handle(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let info = RunningAppInfo(app)
        guard BlockPolicy.shouldBlock(info, allowed: allowed) else { return }

        // Immediately hide all instances so the window disappears without delay.
        app.hide()
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleID) {
            running.hide()
        }
        scheduleRehides(bundleID: info.bundleID)

        let shouldQuit = BlockPolicy.sessionClose(bundleID: info.bundleID) == .quit
        if shouldQuit {
            _ = app.terminate()
            scheduleEscalatedTermination(bundleID: info.bundleID)
        }

        activateFallback()
        if debouncer.shouldCount(info.bundleID, at: Date()) {
            onBlocked?(info)
        }
    }

    private func scheduleRehides(bundleID: String) {
        let runGeneration = generation
        for delay in Self.rehideDelays {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.generation == runGeneration else { return }
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isHidden {
                    app.hide()
                    self.activateFallback()
                }
            }
        }
    }

    private func scheduleEscalatedTermination(bundleID: String) {
        guard !BlockPolicy.neverQuit.contains(bundleID) else { return }
        let runGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, self.generation == runGeneration else { return }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
                app.forceTerminate()
            }
        }
    }

    private func sweepRunningApplications() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ownPID {
            let info = RunningAppInfo(app)
            if BlockPolicy.shouldBlock(info, allowed: allowed) {
                handle(pid: app.processIdentifier)
            }
        }
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func watchdogTick() {
        if let front = NSWorkspace.shared.frontmostApplication {
            let info = RunningAppInfo(front)
            if BlockPolicy.shouldBlock(info, allowed: allowed) {
                handle(pid: front.processIdentifier)
            }
        }
    }

    /// Brings the fallback app to the front; when it is not running, activates our own app instead.
    private func activateFallback() {
        if let fallback = NSRunningApplication.runningApplications(withBundleIdentifier: fallbackBundleID).first {
            fallback.activate()
        } else {
            NSApp.activate()
        }
    }
}
