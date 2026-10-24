import AppKit
import CoreServices

/// Whether Tofu may send Apple Events to an app (Settings › Setup check), asked without showing the macOS prompt.
enum AutomationPermission: Equatable {
    case allowed
    case denied
    /// macOS has not asked yet; the first lock-in (or "Request access") will.
    case notAsked
    /// macOS only answers while the app runs.
    case appNotRunning
    case notInstalled

    /// Never prompts. Can take a moment while the target app is busy, so call it off the main thread.
    static func check(bundleID: String) -> AutomationPermission {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return .notInstalled }
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return .notAsked }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        return from(status: status)
    }

    static func from(status: OSStatus) -> AutomationPermission {
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .appNotRunning
        default: return .notAsked
        }
    }
}
