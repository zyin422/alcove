import AppKit

/// Owns the AppModel, connects the live window presenter, and ends a running session on quit.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var storedModel: AppModel?
    private var presenter: MainWindowPresenter?
    private var wakeObserver: NSObjectProtocol?
    private var sitePrompt: SitePromptController?
    private var endOfDayTimer: Timer?
    private var unlockObserver: NSObjectProtocol?
    private var morning: MorningWindowController?

    /// Created lazily on first access (never during tests).
    var model: AppModel {
        if let storedModel { return storedModel }
        let created = AppModel()
        storedModel = created
        return created
    }

    /// Creates MainWindowPresenter(model:), retains it, assigns model.engine.presenter, lets the assistant bring the
    /// chat screen forward (model.onShowChat) and welcomes the user back when the Mac wakes during a lock-in.
    /// Starts Sparkle (release builds only). No-op under tests.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        let presenter = MainWindowPresenter(model: model)
        self.presenter = presenter
        model.engine.presenter = presenter
        model.onShowChat = { [weak presenter] in presenter?.showMainWindow() }
        let sitePrompt = SitePromptController(assistant: model.assistant)
        self.sitePrompt = sitePrompt
        sitePrompt.onOpenChat = { [weak presenter] in presenter?.showMainWindow() }
        model.assistant.onSiteAsked = { [weak sitePrompt] site in sitePrompt?.present(site) }
        model.assistant.onAssistantMessage = { [weak sitePrompt] text in sitePrompt?.assistantSaid(text) }
        model.onSessionEnded = { [weak self, weak sitePrompt] in
            sitePrompt?.hide()
            self?.storedModel?.checkEndOfDay()
        }
        model.onShowMainWindow = { Self.bringMainWindowForward() }
        let morning = MorningWindowController(model: model)
        self.morning = morning
        model.onShowMorning = { [weak morning] in morning?.show() }
        model.onHideMorning = { [weak morning] in morning?.hide() }
        #if !DEBUG
        // A dev build must not replace itself, so only release builds check for updates.
        model.updates.driver = SparkleUpdater(center: model.updates)
        #endif
        endOfDayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.checkEndOfDay() }
        }
        model.checkMorning()
        model.checkEndOfDay()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storedModel?.systemDidWake()
                self?.storedModel?.checkMorning()
            }
        }
        // Unlocking the screen is the other "start of the day" (the Mac may never have slept).
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.checkMorning() }
        }
    }

    /// model.engine.terminateNow() then model.save(). No-op under tests.
    /// Unhides the apps we hid and records the session as interrupted (no Discord post).
    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests, let storedModel else { return }
        storedModel.engine.terminateNow()
        storedModel.save()
    }

    /// Unminimizes and fronts the main (non-panel) window, e.g. for the end-of-day wrap-up.
    private static func bringMainWindowForward() {
        let window = NSApp.windows.first { !($0 is NSPanel) && $0.sheetParent == nil && $0.canBecomeMain }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
