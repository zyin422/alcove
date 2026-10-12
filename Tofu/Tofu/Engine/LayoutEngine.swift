import CoreGraphics

/// Window frames for one layout preset, in Cocoa coordinates (bottom-left origin).
struct LayoutResult: Equatable {
    /// Chrome window frames, left to right. Count equals `preset.siteCount`.
    var chromeFrames: [CGRect]
    /// Frame for our own window. Non-nil exactly when `preset.appHasZone`.
    var appFrame: CGRect?
}

/// Splits the visible screen area into full-height zones for a layout preset (spec §7).
enum LayoutEngine {
    /// What occupies one zone.
    private enum ZoneKind {
        case chrome
        case app
    }

    /// One zone and its share of the width as an integer weight.
    private struct Zone {
        let kind: ZoneKind
        let weight: Int
    }

    /// Zones left to right. Integer weights keep the arithmetic exact (no 0.7 float drift).
    private static func zones(for preset: LayoutPreset) -> [Zone] {
        switch preset {
        case .split:
            return [Zone(kind: .chrome, weight: 1), Zone(kind: .chrome, weight: 1)]
        case .full:
            return [Zone(kind: .chrome, weight: 1)]
        case .thirds:
            return [Zone(kind: .app, weight: 1), Zone(kind: .chrome, weight: 1), Zone(kind: .chrome, weight: 1)]
        case .mainSide:
            return [Zone(kind: .chrome, weight: 7), Zone(kind: .app, weight: 3)]
        }
    }

    /// `visible` is Cocoa coordinates (bottom-left origin). Zones are full-height, left->right,
    /// widths rounded down to whole points; the last zone absorbs the remainder.
    static func layout(_ preset: LayoutPreset, in visible: CGRect) -> LayoutResult {
        let plan = zones(for: preset)
        let totalWeight = CGFloat(plan.reduce(0) { $0 + $1.weight })
        var result = LayoutResult(chromeFrames: [], appFrame: nil)
        var used: CGFloat = 0
        for (index, zone) in plan.enumerated() {
            let isLast = index == plan.count - 1
            let width = isLast
                ? visible.width - used
                : (visible.width * CGFloat(zone.weight) / totalWeight).rounded(.down)
            let frame = CGRect(x: visible.minX + used, y: visible.minY, width: width, height: visible.height)
            switch zone.kind {
            case .chrome:
                result.chromeFrames.append(frame)
            case .app:
                result.appFrame = frame
            }
            used += width
        }
        return result
    }

    /// Where each of the subject's windows goes (index-aligned with `subject.slots`; nil = wherever it opens)
    /// and our own window's zone. A custom layout uses the slots' frames and has no app zone.
    static func placement(for subject: Subject, visible: CGRect?, primaryHeight: CGFloat)
        -> (slotBounds: [ChromeBounds?], appFrame: CGRect?) {
        guard let visible else { return (subject.slots.map { _ in nil }, nil) }
        if subject.usesCustomLayout {
            return (subject.slots.map { slot in
                slot.frame.map { ScreenGeometry.bounds(for: $0, visible: visible, primaryHeight: primaryHeight) }
            }, nil)
        }
        let result = layout(subject.preset, in: visible)
        let zones = result.chromeFrames.map { ScreenGeometry.chromeBounds(for: $0, primaryHeight: primaryHeight) }
        return (subject.slots.indices.map { $0 < zones.count ? zones[$0] : nil }, result.appFrame)
    }
}
