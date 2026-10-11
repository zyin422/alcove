import AppKit

/// Owns the AppModel, connects the live window presenter, and ends a running session on quit.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var storedModel: AppModel?
    private var presenter: MainWindowPresenter?
    private var wakeObserver: NSObjectProtocol?

    /// Created lazily on first access (never during tests).
    var model: AppModel {
        if let storedModel { return storedModel }
        let created = AppModel()
        storedModel = created
        return created
    }

    /// Creates MainWindowPresenter(model:), retains it, assigns model.engine.presenter, lets the assistant bring the
    /// chat screen forward (model.onShowChat) and welcomes the user back when the Mac wakes during a lock-in.
    /// No-op under tests.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        let presenter = MainWindowPresenter(model: model)
        self.presenter = presenter
        model.engine.presenter = presenter
        model.onShowChat = { [weak presenter] in presenter?.showMainWindow() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storedModel?.systemDidWake() }
        }
    }

    /// model.engine.terminateNow() then model.save(). No-op under tests.
    /// Unhides the apps we hid and records the session as interrupted (no Discord post).
    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests, let storedModel else { return }
        storedModel.engine.terminateNow()
        storedModel.save()
    }
}
