import Foundation

/// Snapshot of a running app, decoupled from `NSRunningApplication` so the rules stay testable.
struct RunningAppInfo: Equatable {
    let bundleID: String
    let name: String
    let isRegular: Bool
}

/// Pure rules for which apps may stay visible while locked in.
enum BlockPolicy {
    /// Chrome, Finder and System Settings (so Chrome Automation can be granted mid-session).
    static let alwaysAllowed: Set<String> = ["com.google.Chrome", "com.apple.finder", "com.apple.systempreferences"]

    /// Never quit by a "Quit them" setup, only hidden: developer tools that may be running this app (or the
    /// assistant the user is coding with), where quitting would lose work or end the session.
    static let neverQuit: Set<String> = [
        "com.apple.finder", "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.todesktop.230313mzl4w4u92", "com.apple.ActivityMonitor", "com.apple.systempreferences",
    ]

    /// alwaysAllowed ∪ {ownBundleID} ∪ the setup's browser and window apps ∪ subject.allowedApps bundle IDs.
    /// Chrome is only allowed when it is the setup's browser. Distraction apps and unmonitored browsers are always excluded.
    static func allowedSet(for subject: Subject, ownBundleID: String) -> Set<String> {
        var allowed = alwaysAllowed
        if subject.browser != .chrome { allowed.remove(Browser.chrome.bundleID) }
        allowed.insert(subject.browser.bundleID)
        allowed.insert(ownBundleID)
        let safeSlotApps = subject.slotApps.map(\.bundleID).filter { !DistractionApps.isDistraction($0) }
        let safeAllowedApps = subject.allowedApps.map(\.bundleID).filter { !DistractionApps.isDistraction($0) }
        allowed.formUnion(safeSlotApps)
        allowed.formUnion(safeAllowedApps)
        return allowed
    }

    /// isRegular && !allowed.contains(bundleID) && !bundleID.isEmpty
    static func shouldBlock(_ app: RunningAppInfo, allowed: Set<String>) -> Bool {
        app.isRegular && !app.bundleID.isEmpty && !allowed.contains(app.bundleID)
    }

    /// A disallowed app that launches or comes forward during a lock-in is quit. Finder and the developer
    /// tools in `neverQuit` are only hidden, so closing them cannot end the session or throw away unsaved work.
    static func sessionClose(bundleID: String) -> UnusedAppsAction {
        neverQuit.contains(bundleID) ? .hide : .quit
    }

    /// How a disallowed app is put away at lock-in. Developer tools are only hidden. Anything else is quit when
    /// the quit message was sent; when it was not, the app is hidden and that hide has to be remembered.
    static func forcedClose(bundleID: String, didSendQuit: Bool) -> UnusedAppsAction {
        if neverQuit.contains(bundleID) || !didSendQuit { return .hide }
        return .quit
    }
}

/// Counts a blocked attempt at most once per `window` seconds per app
/// (a relaunch fires both "launched" and "activated" within milliseconds).
struct AttemptDebouncer {
    var window: TimeInterval
    private var lastCounted: [String: Date] = [:]

    init(window: TimeInterval = 2) { self.window = window }

    /// true if this bundleID was not counted within `window` seconds before `date`; records it when true.
    mutating func shouldCount(_ bundleID: String, at date: Date) -> Bool {
        if let last = lastCounted[bundleID], date.timeIntervalSince(last) < window {
            return false
        }
        lastCounted[bundleID] = date
        return true
    }
}
