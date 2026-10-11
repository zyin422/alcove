import AppKit

/// Chrome AppleScript window `bounds` {left, top, right, bottom}: origin at the top-left
/// of the primary screen, y grows downward, whole points.
struct ChromeBounds: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    /// The same area as a top-left-origin rect (Accessibility positions use this space too).
    var rect: CGRect { CGRect(x: left, y: top, width: right - left, height: bottom - top) }
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

    /// A custom layout's window: `unit` (fractions of the visible area, top-left origin) -> top-left global bounds.
    static func bounds(for unit: UnitRect, visible: CGRect, primaryHeight: CGFloat) -> ChromeBounds {
        let top = primaryHeight - visible.maxY
        let left = visible.minX + unit.x * visible.width
        let upper = top + unit.y * visible.height
        return ChromeBounds(left: wholePoints(left), top: wholePoints(upper),
                            right: wholePoints(left + unit.width * visible.width),
                            bottom: wholePoints(upper + unit.height * visible.height))
    }

    /// The reverse of `bounds(for:visible:primaryHeight:)`: a top-left global rect (as CGWindowList and
    /// Accessibility report it) -> fractions of the visible area, clamped to it.
    static func unitRect(for rect: CGRect, visible: CGRect, primaryHeight: CGFloat) -> UnitRect {
        guard visible.width > 0, visible.height > 0 else { return UnitRect(x: 0, y: 0, width: 1, height: 1) }
        let top = primaryHeight - visible.maxY
        func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
        let x = clamp((rect.minX - visible.minX) / visible.width)
        let y = clamp((rect.minY - top) / visible.height)
        let maxX = clamp((rect.maxX - visible.minX) / visible.width)
        let maxY = clamp((rect.maxY - top) / visible.height)
        return UnitRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
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
