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

    /// Black or white, whichever reads better on `background` (the higher WCAG contrast ratio).
    static func readableText(on background: SidebarPalette.HSL) -> Color {
        prefersDarkText(on: background) ? .black : .white
    }

    /// True when black text has more contrast than white on `background`.
    static func prefersDarkText(on background: SidebarPalette.HSL) -> Bool {
        let c = SidebarPalette.rgb(background)
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        // Contrast with black is (L + 0.05) / 0.05, with white 1.05 / (L + 0.05); they are equal at L ≈ 0.179.
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }

    /// Sizing for the pages in the detail card. Content uses the card's width; only prose keeps a reading width.
    enum Page {
        /// The widest a page's content column gets (about Tailwind's `max-w-7xl`); past it the column is centered,
        /// so a full-screen window on a large display doesn't stretch a text field across the whole screen.
        static let maxContentWidth: CGFloat = 1320
        /// A comfortable line length for long prose, such as the setup agent's replies.
        static let readingWidth: CGFloat = 640
        /// Column width from which the subject form puts its sections side by side.
        static let twoColumnWidth: CGFloat = 1000
        /// Column width below which page headers drop secondary labels (shortcut hints, segment titles).
        static let compactHeaderWidth: CGFloat = 640

        /// Padding around a page: 24 pt on a small card, growing with the card's width up to 56 pt.
        static func padding(forWidth width: CGFloat) -> CGFloat {
            min(max(width * 0.04, Space.l), 56).rounded()
        }

        /// The width left for content once the column is capped at `maxWidth` and padded.
        static func contentWidth(forWidth width: CGFloat, maxWidth: CGFloat = maxContentWidth) -> CGFloat {
            max(min(width, maxWidth) - padding(forWidth: width) * 2, 0)
        }
    }
}

/// What a page knows about the space it was given: the content column's width and the visible height.
struct PageMetrics: Equatable {
    var contentWidth: CGFloat
    var visibleHeight: CGFloat
    var isCompact: Bool { contentWidth < Theme.Page.compactHeaderWidth }
}

/// A detail page's scrolling column. The content spans the card up to `maxWidth` (then is centered), with padding
/// that scales a little with the width, and scrolls when it is taller than the card.
/// With `fillsHeight` the content is offered at least the visible height, so a child with `maxHeight: .infinity`
/// (the setup chat, a spacer above a footer) fills the page. Text in such a page should be `fixedSize` vertically,
/// or a short window squeezes it instead of scrolling.
struct PageScrollView<Content: View>: View {
    var maxWidth: CGFloat = Theme.Page.maxContentWidth
    var fillsHeight = false
    @ViewBuilder var content: (PageMetrics) -> Content

    var body: some View {
        GeometryReader { proxy in
            let padding = Theme.Page.padding(forWidth: proxy.size.width)
            let metrics = PageMetrics(contentWidth: Theme.Page.contentWidth(forWidth: proxy.size.width, maxWidth: maxWidth),
                                      visibleHeight: proxy.size.height)
            ScrollView {
                content(metrics)
                    .padding(padding)
                    .frame(maxWidth: maxWidth, minHeight: fillsHeight ? proxy.size.height : nil, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
            }
        }
    }
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
