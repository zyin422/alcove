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

    static func subjectColor(_ hex: String) -> Color {
        let parts = SubjectColor.components(hex)
        return Color(red: parts.red, green: parts.green, blue: parts.blue)
    }

    // MARK: - Semantic Color Palette
    /// Warm analog amber for countdowns, telemetry, and between-block grace.
    static let amber = Color(red: 0.851, green: 0.467, blue: 0.024)   // #D97706
    /// Fresh sage emerald for completed priorities, lock-in confirmation, and verified work.
    static let emerald = Color(red: 0.020, green: 0.588, blue: 0.412) // #059669
    /// Vibrant indigo for deep work sessions, planning mode, and primary action controls.
    static let indigo = Color(red: 0.310, green: 0.275, blue: 0.898)  // #4F46E5
    /// Electric cyan for calendar rhythm and schedule tracking.
    static let cyan = Color(red: 0.008, green: 0.518, blue: 0.780)    // #0284C7
    /// Apricot coral for break intervals and restorative rest.
    static let coral = Color(red: 0.918, green: 0.345, blue: 0.047)   // #EA580C
    /// Vivid rose for closed tab notices and distraction firewall interventions.
    static let rose = Color(red: 0.882, green: 0.114, blue: 0.282)    // #E11D48
    /// Midnight violet for bedtime wind-down and nocturnal guard.
    static let violet = Color(red: 0.486, green: 0.227, blue: 0.929)  // #7C3AED
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
