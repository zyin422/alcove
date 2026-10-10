import AppKit

@MainActor protocol WorkspaceControlling: AnyObject {
    /// Hides every running .regular app not in `allowed` and not already hidden. Returns bundle IDs hidden.
    func hideOthers(allowed: Set<String>) -> [String]
    /// Unhides running apps with these bundle IDs.
    func unhide(_ bundleIDs: [String])
    func activate(bundleID: String)
}

extension RunningAppInfo {
    /// Snapshot of a live app. A missing bundle ID becomes "" (never blocked); a missing name falls back to the bundle ID.
    init(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        self.init(bundleID: bundleID,
                  name: app.localizedName ?? bundleID,
                  isRegular: app.activationPolicy == .regular)
    }
}

/// Hides and unhides other apps through NSWorkspace / NSRunningApplication. Never quits anything.
@MainActor final class WorkspaceController: WorkspaceControlling {
    init() {}

    func hideOthers(allowed: Set<String>) -> [String] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var hidden: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ownPID, !app.isHidden else { continue }
            let info = RunningAppInfo(app)
            guard BlockPolicy.shouldBlock(info, allowed: allowed) else { continue }
            if app.hide(), !hidden.contains(info.bundleID) {
                hidden.append(info.bundleID)
            }
        }
        return hidden
    }

    func unhide(_ bundleIDs: [String]) {
        var seen = Set<String>()
        for bundleID in bundleIDs where seen.insert(bundleID).inserted {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.isHidden {
                app.unhide()
            }
        }
    }

    func activate(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }
}
