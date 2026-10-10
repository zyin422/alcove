import Foundation

/// Snapshot of a running app, decoupled from `NSRunningApplication` so the rules stay testable.
struct RunningAppInfo: Equatable {
    let bundleID: String
    let name: String
    let isRegular: Bool
}

/// Pure rules for which apps may stay visible while locked in.
enum BlockPolicy {
    static let alwaysAllowed: Set<String> = ["com.google.Chrome", "com.apple.finder"]

    /// alwaysAllowed ∪ {ownBundleID} ∪ subject.allowedApps bundle IDs.
    static func allowedSet(for subject: Subject, ownBundleID: String) -> Set<String> {
        var allowed = alwaysAllowed
        allowed.insert(ownBundleID)
        allowed.formUnion(subject.allowedApps.map(\.bundleID))
        return allowed
    }

    /// isRegular && !allowed.contains(bundleID) && !bundleID.isEmpty
    static func shouldBlock(_ app: RunningAppInfo, allowed: Set<String>) -> Bool {
        app.isRegular && !app.bundleID.isEmpty && !allowed.contains(app.bundleID)
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
