import AppKit

/// Quit is refused while a work block is running. Force Quit from outside the app is the only way out.
enum QuitPolicy {
    static func allowsQuit(isLocked: Bool) -> Bool { !isLocked }
}

/// Owns the AppModel, connects the live window presenter, and ends a running session on quit.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var storedModel: AppModel?
    private var presenter: MainWindowPresenter?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var sitePrompt: SitePromptController?
    private var endOfDayTimer: Timer?
    private var unlockObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var morning: MorningWindowController?
    private var bedtime: BedtimeWindowController?

    /// Created lazily on first access (never during tests).
    var model: AppModel {
        if let storedModel { return storedModel }
        let created = AppModel()
        storedModel = created
        return created
    }

    /// Creates MainWindowPresenter(model:), retains it, assigns model.engine.presenter, lets the assistant bring the
    /// chat screen forward (model.onShowChat) and welcomes the user back when the Mac wakes during a lock-in.
    /// Starts Sparkle (builds made by scripts/release.sh only). No-op under tests.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        let presenter = MainWindowPresenter(model: model)
        self.presenter = presenter
        model.engine.presenter = presenter
        model.onShowChat = { [weak presenter] in presenter?.showMainWindow() }
        model.engine.onSpirit = { [weak presenter] notice in presenter?.note(notice) }
        let sitePrompt = SitePromptController(assistant: model.assistant)
        self.sitePrompt = sitePrompt
        sitePrompt.onOpenChat = { [weak presenter] in presenter?.showMainWindow() }
        model.assistant.onSiteAsked = { [weak sitePrompt, weak presenter] site in
            sitePrompt?.present(site)
            presenter?.note(.question(host: site.host, title: site.title))
        }
        model.assistant.onAssistantMessage = { [weak sitePrompt] text in sitePrompt?.assistantSaid(text) }
        model.onSessionEnded = { [weak self, weak sitePrompt] in
            sitePrompt?.hide()
            self?.storedModel?.checkEndOfDay()
            self?.storedModel?.checkBedtime()
        }
        model.onShowMainWindow = { Self.bringMainWindowForward() }
        let morning = MorningWindowController(model: model)
        self.morning = morning
        model.onShowMorning = { [weak morning] in morning?.show() }
        model.onHideMorning = { [weak morning] in morning?.hide() }
        let bedtime = BedtimeWindowController(model: model)
        self.bedtime = bedtime
        model.onShowBedtime = { [weak bedtime] in bedtime?.show() }
        model.onHideBedtime = { [weak bedtime] in bedtime?.hide() }
        #if TOFU_RELEASE
        // Only builds made by scripts/release.sh check for updates; a build from source must not replace itself.
        model.updates.driver = SparkleUpdater(center: model.updates)
        #endif
        endOfDayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storedModel?.checkMorning()
                self?.storedModel?.checkEndOfDay()
                self?.storedModel?.checkBedtime()
            }
        }
        Task { @MainActor in
            await model.continueBlockIfNeeded()
            model.checkMorning()
            model.checkEndOfDay()
            model.checkBedtime()
        }
        let workspaceNotes = NSWorkspace.shared.notificationCenter
        sleepObserver = workspaceNotes.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.systemWillSleep() }
        }
        wakeObserver = workspaceNotes.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storedModel?.systemDidWake()
                self?.storedModel?.checkMorning()
                self?.storedModel?.checkBedtime()
            }
        }
        // Unlocking the screen is the other "start of the day" (the Mac may never have slept).
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storedModel?.checkMorning()
                self?.storedModel?.checkBedtime()
            }
        }
        let screens = NSWorkspace.shared.notificationCenter
        screenSleepObserver = screens.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.displayWillSleep() }
        }
        screenWakeObserver = screens.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.displayDidWake() }
        }
    }

    /// model.engine.terminateNow() then model.save(). No-op under tests.
    /// Unhides the apps we hid and records the session as interrupted (no Discord post).
    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests, let storedModel else { return }
        storedModel.engine.terminateNow()
        storedModel.save()
    }

    /// A dock click brings the window we already have. A new one would sit beside it after lock-in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presenter?.showExistingWindow()
        return false
    }

    /// Cmd-Q, the Quit menu, and a Dock quit all ask here. A running block stays running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.isRunningTests { return .terminateNow }
        let locked = storedModel?.engine.isLocked == true
        guard QuitPolicy.allowsQuit(isLocked: locked) else {
            ToastCenter.shared.show("Quit is off until this block ends.")
            return .terminateCancel
        }
        return .terminateNow
    }

    /// Unminimizes and fronts the main (non-panel) window, e.g. for the end-of-day wrap-up.
    private static func bringMainWindowForward() {
        let window = MainWindowPresenter.visibleMainWindow()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
