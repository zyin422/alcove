import AppKit

/// Chrome AppleScript window `bounds` {left, top, right, bottom}: origin at the top-left
/// of the primary screen, y grows downward, whole points.
struct ChromeBounds: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

/// Converts Cocoa screen rects into Chrome's AppleScript coordinate space (spec §7).
enum ScreenGeometry {
    /// Cocoa rect -> Chrome AppleScript bounds (top-left origin of primary screen, y down).
    static func chromeBounds(for rect: CGRect, primaryHeight: CGFloat) -> ChromeBounds {
        ChromeBounds(left: wholePoints(rect.minX),
                     top: wholePoints(primaryHeight - rect.maxY),
                     right: wholePoints(rect.maxX),
                     bottom: wholePoints(primaryHeight - rect.minY))
    }

    /// Visible frame (menu bar and Dock excluded) of the main screen, else the first screen; nil with no screen.
    @MainActor static func mainVisibleFrame() -> CGRect? {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    }

    /// Height of the primary screen (`NSScreen.screens[0]`), or 0 when there is no screen.
    @MainActor static func primaryHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Largest magnitude we convert; real screens are far smaller. Keeps `Int(_:)` from trapping.
    private static let limit: CGFloat = 1_000_000

    /// Rounds to the nearest whole point. Non-finite values become 0 and huge values are clamped.
    private static func wholePoints(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), -limit), limit))
    }
}
