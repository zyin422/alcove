import AppKit
import SwiftUI

/// Arc-style window chrome: one hue becomes a gradient behind the sidebar plus matching text colors, the way
/// Arc derives a Space's palette from its color. Each subject gets a stable hue; Today, Stats and Settings use
/// `defaultHue`. Pure, so the colors are testable.
struct SidebarPalette: Equatable {
    /// Hue (degrees), saturation and lightness (0...100) of one color.
    struct HSL: Equatable {
        var h: Double
        var s: Double
        var l: Double
    }

    var top: HSL
    var bottom: HSL
    var foreground: HSL
    var secondary: HSL

    /// Soft violet, close to Arc's default Space.
    static let defaultHue: Double = 250
    static let defaultSaturation: Double = 35
    /// Hues a subject can get. Spaced so that neighbouring subjects rarely look alike.
    static let subjectHues: [Double] = [250, 215, 185, 150, 95, 40, 15, 340, 290]
    static let subjectSaturation: Double = 55

    /// Same formula as the Arc clone's `paletteFor`: light chrome is a pale tint, dark chrome a deep shade.
    static func make(hue: Double, saturation: Double, dark: Bool) -> SidebarPalette {
        let sat = min(saturation, 70)
        if dark {
            return SidebarPalette(top: HSL(h: hue, s: sat * 0.55, l: 22),
                                  bottom: HSL(h: hue + 12, s: sat * 0.5, l: 13),
                                  foreground: HSL(h: hue, s: 30, l: 96),
                                  secondary: HSL(h: hue, s: 18, l: 74))
        }
        return SidebarPalette(top: HSL(h: hue, s: sat, l: 86),
                              bottom: HSL(h: hue + 14, s: sat * 0.9, l: 74),
                              foreground: HSL(h: hue, s: 45, l: 14),
                              secondary: HSL(h: hue, s: 22, l: 32))
    }

    /// The palette for what the sidebar has selected.
    static func make(for selection: SidebarItem?, dark: Bool) -> SidebarPalette {
        if case .subject(let id) = selection {
            return make(hue: hue(for: id), saturation: subjectSaturation, dark: dark)
        }
        return make(hue: defaultHue, saturation: defaultSaturation, dark: dark)
    }

    /// A subject's hue, stable across launches (FNV-1a over the id; `hashValue` is seeded per process).
    static func hue(for subjectID: UUID) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in subjectID.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return subjectHues[Int(hash % UInt64(subjectHues.count))]
    }

    /// RGB components (0...1) of an HSL color.
    static func rgb(_ color: HSL) -> (r: Double, g: Double, b: Double) {
        let h = (color.h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(max(color.s, 0), 100) / 100
        let l = min(max(color.l, 0), 100) / 100
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }

    static func color(_ hsl: HSL) -> Color {
        let c = rgb(hsl)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Self.color(top), Self.color(bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var foregroundColor: Color { Self.color(foreground) }
    var secondaryColor: Color { Self.color(secondary) }
}

/// Row fills on the tinted chrome: a faint wash on hover, a lifted pill when selected.
enum SidebarFill {
    static func hover(dark: Bool) -> Color { dark ? .white.opacity(0.08) : .black.opacity(0.07) }
    static func selected(dark: Bool) -> Color { dark ? .white.opacity(0.18) : .white.opacity(0.6) }
    static func tile(dark: Bool) -> Color { dark ? .white.opacity(0.1) : .white.opacity(0.35) }
    static func tileHover(dark: Bool) -> Color { dark ? .white.opacity(0.16) : .white.opacity(0.5) }
}

/// Transparent strip that moves the window when dragged, for the title-bar area the sidebar draws into.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
