import AppKit
import os

/// Opens a setup's apps at lock-in.
@MainActor protocol SetupLaunching: AnyObject {
    /// Opens `app` (on `folder` when given) and moves its window to `bounds` when given.
    /// Returns a short message for a toast when something went wrong, nil when it worked.
    func open(_ app: AllowedApp, folder: String?, bounds: ChromeBounds?) async -> String?
}

/// Live `SetupLaunching`: NSWorkspace opens the app (and folder), `WindowPlacer` moves its window.
/// Does not raise the system Accessibility dialog on later lock-ins once this build has asked.
@MainActor final class SetupLauncher: SetupLaunching {
    /// One explanation per launch. The system dialog itself is limited to once per build.
    private var didExplain = false

    func open(_ app: AllowedApp, folder: String?, bounds: ChromeBounds?) async -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return "\(app.name) isn't installed"
        }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if let folder = Self.expandedPath(folder) {
                guard FileManager.default.fileExists(atPath: folder) else { return "Folder not found: \(folder)" }
                _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: appURL,
                                                      configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
        } catch {
            Log.session.error("Opening \(app.bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return "Couldn't open \(app.name)"
        }
        guard let bounds else { return nil }
        if !WindowPlacer.isTrusted {
            let stamp = AccessibilityGate.buildStamp()
            if AccessibilityGate.shouldPrompt(trusted: false, stamp: stamp,
                                               lastPrompt: UserDefaults.standard.string(forKey: AccessibilityGate.promptKey)) {
                UserDefaults.standard.set(stamp, forKey: AccessibilityGate.promptKey)
                WindowPlacer.requestAccess()
            }
        }
        guard WindowPlacer.isTrusted else {
            // The prompt returns immediately. If they allow it in the next half minute, still place this window.
            let bundleID = app.bundleID
            Task {
                guard await WindowPlacer.waitUntilTrusted(seconds: 30) else { return }
                let placed = await WindowPlacer.place(bundleID: bundleID, bounds: bounds, settle: 0.3, timeout: 6)
                if placed { await WindowPlacer.keep(bundleID: bundleID, bounds: bounds, seconds: 12) }
            }
            if didExplain { return nil }
            didExplain = true
            return "\(app.name) stays at its old size until Tofu is allowed in Accessibility. A switch left on for an older copy does not cover this one — remove that row, then allow it again."
        }
        // A running app opening a folder shows a new window a moment later; let it become the focused one.
        let placed = await WindowPlacer.place(bundleID: app.bundleID, bounds: bounds, settle: wasRunning ? 1.2 : 0.6)
        guard placed else { return "Couldn't place \(app.name)'s window" }
        // VS Code restores its saved size a few seconds after launch. Keep correcting after lock-in continues.
        let bundleID = app.bundleID
        Task { await WindowPlacer.keep(bundleID: bundleID, bounds: bounds, seconds: 12) }
        return nil
    }

    /// "~/code/cs128" -> "/Users/…/code/cs128"; nil for nil or blank.
    nonisolated static func expandedPath(_ path: String?) -> String? {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }
}
