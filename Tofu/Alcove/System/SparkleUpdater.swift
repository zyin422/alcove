import Sparkle

/// Runs Sparkle with gentle reminders: an update found by the daily check goes to the sidebar card (UpdateCenter)
/// instead of a window. The card's Update button and the Check for Updates menu item open Sparkle's window, which
/// downloads, verifies, installs and relaunches. Sparkle calls the delegate on the main thread.
@MainActor final class SparkleUpdater: NSObject, UpdateDriving, SPUStandardUserDriverDelegate {
    /// The center owns this updater (as its driver), so this side doesn't retain it.
    private unowned let center: UpdateCenter
    private var controller: SPUStandardUpdaterController!

    init(center: UpdateCenter) {
        self.center = center
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { center.updateFound(version: version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { center.hide() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { center.hide() }
    }
}
