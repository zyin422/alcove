import AppKit
import ApplicationServices

/// When to show the Accessibility prompt. macOS shows that dialog again if we ask while the
/// checkbox is already on, including after a rebuild that used a new ad-hoc signature.
enum AccessibilityGate {
    static let promptKey = "accessibilityPromptStamp"

    /// Ask once for this build. A later lock-in of the same build must not raise the dialog again.
    static func shouldPrompt(trusted: Bool, stamp: String, lastPrompt: String?) -> Bool {
        !trusted && !stamp.isEmpty && lastPrompt != stamp
    }

    /// Identifies the running binary. A new build gets a new stamp, so it may ask once.
    static func buildStamp() -> String {
        guard let url = Bundle.main.executableURL else { return "" }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(modified)"
    }
}

/// Moves and resizes other apps' windows with the Accessibility API (needs the Accessibility permission).
/// Positions are top-left global coordinates, the same space as `ChromeBounds`.
@MainActor enum WindowPlacer {
    /// True when this process may move other apps' windows. `AXIsProcessTrusted` stays false until
    /// relaunch after the checkbox is turned on, so a windows query is the live check. The system-wide
    /// focused-application attribute succeeds with no permission and must not be used here.
    static var isTrusted: Bool {
        if AXIsProcessTrusted() { return true }
        return canReadOtherAppsWindows()
    }

    /// A windows query is refused with `kAXErrorAPIDisabled` until Accessibility is granted.
    private static func canReadOtherAppsWindows() -> Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != own && $0.activationPolicy == .regular
        }) else { return false }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(AXUIElementCreateApplication(other.processIdentifier),
                                              kAXWindowsAttribute as CFString, &value) == .success
    }

    /// Polls until a windows query is allowed, or `seconds` pass. The system dialog does not block the caller.
    static func waitUntilTrusted(seconds: TimeInterval) async -> Bool {
        if isTrusted { return true }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if isTrusted { return true }
        }
        return false
    }

    /// Shows the system prompt that leads to System Settings › Privacy & Security › Accessibility.
    @discardableResult
    static func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Waits for the app to have a window, then moves it to `bounds`. Success means an on-screen window
    /// actually fills `bounds`, not merely that a resize was requested. The window the app just opened is
    /// preferred; otherwise the largest one. False without permission or when the size never sticks.
    @discardableResult
    static func place(bundleID: String, bounds: ChromeBounds, settle: TimeInterval = 0.4,
                      timeout: TimeInterval = 8) async -> Bool {
        guard isTrusted else { return false }
        let existing = windowFrames(bundleID: bundleID)
        if settle > 0 { try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000)) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if nudge(bundleID: bundleID, bounds: bounds, existing: existing) {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if fills(bundleID: bundleID, bounds: bounds) { return true }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return fills(bundleID: bundleID, bounds: bounds)
    }

    /// Puts the window back whenever the app restores its old size. Lock-in continues while this runs.
    static func keep(bundleID: String, bounds: ChromeBounds, seconds: TimeInterval) async {
        guard isTrusted else { return }
        let existing = windowFrames(bundleID: bundleID)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !fills(bundleID: bundleID, bounds: bounds) {
                nudge(bundleID: bundleID, bounds: bounds, existing: existing)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    /// True when one of the app's on-screen windows fills `bounds`.
    static func fills(bundleID: String, bounds: ChromeBounds) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        return onScreenFrames(pid: app.processIdentifier).contains { WindowChoice.matches($0, bounds.rect) }
    }

    /// Moves the chosen window onto `bounds` unless an on-screen window already fills it. True in that case.
    @discardableResult
    private static func nudge(bundleID: String, bounds: ChromeBounds, existing: [CGRect]) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        if fills(bundleID: bundleID, bounds: bounds) { return true }
        let pairs = windows(of: app.processIdentifier).compactMap { window -> (CGRect, AXUIElement)? in
            frame(of: window).map { ($0, window) }
        }
        guard let index = WindowChoice.index(frames: pairs.map(\.0), existing: existing) else { return false }
        setFrame(of: pairs[index].1, to: bounds.rect)
        return false
    }

    private static func windowFrames(bundleID: String) -> [CGRect] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap { app in
            windows(of: app.processIdentifier).compactMap { frame(of: $0) }
        }
    }

    /// Position, then size, then position again: some apps clamp the size to the screen at the old position.
    /// Electron apps ignore the size while enhanced accessibility UI is on, so that is turned off for the write.
    static func setFrame(of window: AXUIElement, to rect: CGRect) {
        withoutEnhancedUI(window) {
            write(window, rect)
            // A window pressed against the screen edge cannot grow. Park it where the target size fits, then
            // move it onto the target.
            if let now = frame(of: window), !WindowChoice.matches(now, rect, tolerance: 8) {
                var parked = rect
                parked.origin.x = min(rect.minX, now.minX)
                parked.origin.y = min(rect.minY, now.minY)
                write(window, parked)
                write(window, rect)
            }
        }
    }

    private static func write(_ window: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    /// `AXEnhancedUserInterface` makes VS Code and other Electron apps refuse a size change.
    private static func withoutEnhancedUI(_ window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { body(); return }
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        var previous: CFTypeRef?
        AXUIElementCopyAttributeValue(app, key, &previous)
        AXUIElementSetAttributeValue(app, key, kCFBooleanFalse)
        body()
        if let previous { AXUIElementSetAttributeValue(app, key, previous) }
    }

    /// On-screen window frames for `pid` (top-left global, the same space as Accessibility).
    static func onScreenFrames(pid: pid_t) -> [CGRect] {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                               width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            guard frame.width >= 80, frame.height >= 80 else { return nil }
            return frame
        }
    }

    /// The window's frame in top-left global coordinates.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copy(window, kAXPositionAttribute),
              let sizeValue: AXValue = copy(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The file a window shows (`AXDocument`, a file URL string), when the app reports one.
    static func document(of window: AXUIElement) -> URL? {
        guard let text: String = copy(window, kAXDocumentAttribute) else { return nil }
        return URL(string: text)
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                            kAXWindowsAttribute as CFString, &value) == .success,
              let value else { return [] }
        // `copy`'s generic `as? T` does not bridge a CFArray into `[AXUIElement]`, so it always
        // looked like the app had no windows and split/custom placement never resized them.
        if let windows = value as? [AXUIElement], !windows.isEmpty { return windows }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        let array = value as! CFArray
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            return Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue()
        }
    }

    /// Which window of an app should be moved into a zone.
    enum WindowChoice {
        /// A window the app did not already have, when one exists; otherwise the largest. Nil for no windows.
        static func index(frames: [CGRect], existing: [CGRect]) -> Int? {
            guard !frames.isEmpty else { return nil }
            let fresh = frames.indices.filter { index in
                !existing.contains { matches(frames[index], $0, tolerance: 8) }
            }
            let pool = fresh.isEmpty ? Array(frames.indices) : Array(fresh)
            return pool.max { frames[$0].width * frames[$0].height < frames[$1].width * frames[$1].height }
        }

        /// True when `frame` fills `target`. A few points of difference are the title bar and window shadow.
        static func matches(_ frame: CGRect, _ target: CGRect, tolerance: CGFloat = 28) -> Bool {
            abs(frame.minX - target.minX) <= tolerance && abs(frame.minY - target.minY) <= tolerance
                && abs(frame.width - target.width) <= tolerance && abs(frame.height - target.height) <= tolerance
        }
    }

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
