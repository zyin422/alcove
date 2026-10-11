import AppKit

@MainActor protocol WorkspaceControlling: AnyObject {
    /// Hides every running .regular app not in `allowed` and not already hidden. Returns bundle IDs hidden.
    func hideOthers(allowed: Set<String>) -> [String]
    /// Unhides running apps with these bundle IDs.
    func unhide(_ bundleIDs: [String])
    func activate(bundleID: String)
    /// Asks every running .regular app not in `allowed` to quit (it may ask to save first); apps in
    /// `BlockPolicy.neverQuit` are hidden instead. Returns the bundle IDs asked to quit and those hidden.
    func quitOthers(allowed: Set<String>) -> (quit: [String], hidden: [String])
    /// Opens these apps again in the background (skipping ones already running).
    func relaunch(_ bundleIDs: [String])
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

/// Hides, unhides, quits and relaunches other apps through NSWorkspace / NSRunningApplication.
/// Quitting is a normal quit request (never a force quit), so apps can ask to save.
@MainActor final class WorkspaceController: WorkspaceControlling {
    func quitOthers(allowed: Set<String>) -> (quit: [String], hidden: [String]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var quit: [String] = []
        var hidden: [String] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ownPID {
            let info = RunningAppInfo(app)
            guard BlockPolicy.shouldBlock(info, allowed: allowed) else { continue }
            if BlockPolicy.neverQuit.contains(info.bundleID) {
                if !app.isHidden, app.hide(), !hidden.contains(info.bundleID) { hidden.append(info.bundleID) }
            } else {
                app.hide()
                if app.terminate(), !quit.contains(info.bundleID) { quit.append(info.bundleID) }
            }
        }
        return (quit, hidden)
    }

    func relaunch(_ bundleIDs: [String]) {
        var seen = Set<String>()
        for bundleID in bundleIDs where seen.insert(bundleID).inserted {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        }
    }

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
