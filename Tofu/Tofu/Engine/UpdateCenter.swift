import Observation

/// Starts Sparkle's update window. SparkleUpdater in release builds; a fake in tests.
@MainActor protocol UpdateDriving: AnyObject {
    func checkForUpdates()
}

/// What the sidebar's update card shows. Sparkle reports an update found by its daily check here instead of opening
/// its own window; the card's Update button and the Check for Updates menu item hand back to Sparkle.
@Observable @MainActor final class UpdateCenter {
    /// Nil in tests and Debug builds, where Sparkle never starts.
    var driver: (any UpdateDriving)?
    /// The version on the card; nil hides the card.
    private(set) var availableVersion: String?
    /// The version the user closed the card for. In memory only, so a relaunch shows it again.
    private var dismissedVersion: String?

    var canCheckForUpdates: Bool { driver != nil }

    init(driver: (any UpdateDriving)? = nil) {
        self.driver = driver
    }

    func updateFound(version: String) {
        guard version != dismissedVersion else { return }
        availableVersion = version
    }

    /// × on the card: hide it and skip this version until the next launch.
    func dismiss() {
        if let availableVersion { dismissedVersion = availableVersion }
        availableVersion = nil
    }

    /// Opens Sparkle's window, which takes over from the card.
    func checkNow() {
        availableVersion = nil
        driver?.checkForUpdates()
    }

    /// Sparkle has the user's attention or finished its session; the card goes without counting as dismissed.
    func hide() {
        availableVersion = nil
    }
}
