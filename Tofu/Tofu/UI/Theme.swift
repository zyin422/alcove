import AppKit
import SwiftUI

/// Monochrome design tokens (spec §11): grays only, no accent color.
enum Theme {
    static let radius: CGFloat = 10
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }
    /// Five grays from strongest to lightest, for stacked chart series.
    static let grays: [Color] = [
        Color.primary,
        Color.primary.opacity(0.7),
        Color.primary.opacity(0.5),
        Color.primary.opacity(0.32),
        Color.primary.opacity(0.18),
    ]
    static func gray(at index: Int) -> Color { grays[index % grays.count] }
    static func timerFont(size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .monospaced).monospacedDigit()
    }
    static let titleFont = Font.system(size: 34, weight: .semibold)
    static let captionFont = Font.system(size: 11, weight: .medium).smallCaps()
}

/// Solid fill in the label color (black in light mode, white in dark) with inverted text.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Outlined with a 1 pt border in the label color.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 32)
            .foregroundStyle(Color.primary)
            .background(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Small-caps title over a large number, in a hairline-bordered box.
struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}
