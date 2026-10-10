import SwiftUI

/// Small diagram of a layout preset: Chrome zones outlined, the app zone filled, and a mini-timer
/// bar at the top for presets without an app zone. Zones come from `LayoutEngine`, so the picture
/// always matches the real tiling.
struct PresetThumbnail: View {
    let preset: LayoutPreset

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width > 12 && size.height > 12 {
                let layout = LayoutEngine.layout(preset, in: CGRect(origin: .zero, size: size))
                ZStack {
                    ForEach(Array(layout.chromeFrames.enumerated()), id: \.offset) { _, frame in
                        zone(frame).stroke(Color.primary, lineWidth: 1)
                    }
                    if let appFrame = layout.appFrame {
                        zone(appFrame).fill(Color.primary.opacity(0.85))
                    }
                    if !preset.appHasZone {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: size.width * 0.24, height: max(3, size.height * 0.06))
                            .position(x: size.width / 2, y: max(5, size.height * 0.1))
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("\(preset.title) layout"))
    }

    /// A zone inset by 1.5 pt so neighbouring zones show a gap.
    private func zone(_ frame: CGRect) -> some Shape {
        let inset = frame.insetBy(dx: 1.5, dy: 1.5)
        return RoundedRectangle(cornerRadius: 2).path(in: inset)
    }
}
