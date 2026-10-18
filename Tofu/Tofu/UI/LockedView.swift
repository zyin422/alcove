import AppKit
import SwiftUI

extension Color {
    /// Pure white in light mode and pure black in dark mode: the background of the lock-in screens.
    static let lockBackground = Color(nsColor: NSColor(name: "lockBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    })
}

/// Pure layout and text rules for the locked main window (unit-tested).
enum LockedLayout {
    /// Size of the main window when it is brought up from the mini timer.
    static let windowSize = CGSize(width: 900, height: 600)

    /// Window width below which the session info stacks on top of the chat instead of sitting beside it.
    static let stackedBelowWidth: CGFloat = 640
    /// Width of the session info pane beside the chat.
    static let sidePaneWidth: CGFloat = 280
    /// Smallest the chat column may get beside the info pane.
    static let chatMinWidth: CGFloat = 360
    /// Largest timer size in the info pane.
    static let sideTimerMaxFontSize: CGFloat = 44

    /// True when a window of `width` is too narrow for chat and info side by side.
    static func isStacked(width: CGFloat) -> Bool {
        width < stackedBelowWidth
    }

    /// Timer size for an info pane `paneWidth` wide (content width): 44 pt, smaller when the pane is narrow.
    static func sideTimerFontSize(paneWidth: CGFloat) -> CGFloat {
        min(sideTimerMaxFontSize, timerFontSize(for: CGSize(width: paneWidth, height: 200)))
    }

    /// Timer font size for the space it gets: min(width / 5, height * 0.42), never below 1 pt.
    static func timerFontSize(for size: CGSize) -> CGFloat {
        let fitted = min(size.width / 5.0, size.height * 0.42)
        guard fitted.isFinite else { return 1 }
        return max(1, fitted)
    }

    /// Goal progress from 0 to 1. A goal of zero or less counts as reached.
    static func progress(elapsed: TimeInterval, goal: TimeInterval) -> Double {
        guard goal > 0 else { return 1 }
        return min(1, max(0, elapsed / goal))
    }

    /// "3 apps blocked · 2 tabs closed", singular for 1.
    static func countersText(blocked: Int, tabs: Int) -> String {
        let apps = blocked == 1 ? "app" : "apps"
        let tabWord = tabs == 1 ? "tab" : "tabs"
        return "\(blocked) \(apps) blocked · \(tabs) \(tabWord) closed"
    }

    /// "goal 50m", "goal 1h 30m".
    static func goalCaption(goalSeconds: TimeInterval) -> String {
        "goal \(TimeFormat.short(goalSeconds))"
    }

    /// `size` centered in `visible`, shrunk to fit when the screen is smaller. Origin rounded down to whole points.
    static func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = visible.minX + ((visible.width - width) / 2).rounded(.down)
        let y = visible.minY + ((visible.height - height) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Chat screen shown in the main window while locked: the conversation with the study buddy on the left, a
/// compact session pane (subject, timer, goal progress, counters, End) on the right. Below 640 pt of width the
/// pane stacks on top of the chat. It re-renders every tick because it reads `engine.now` (through
/// `elapsed`/`remaining`). The mini timer's ✕ starts the same end flow as the End button.
struct LockedView: View {
    let model: AppModel
    @State private var isShowingMirror = false

    var body: some View {
        GeometryReader { proxy in
            let stacked = LockedLayout.isStacked(width: proxy.size.width)
            // AnyLayout keeps the chat's identity (typed text, open microphone) when the window crosses the breakpoint.
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                if stacked {
                    stackedInfo(engine: model.engine, width: proxy.size.width)
                    separator(stacked: true)
                }
                ChatView(assistant: model.assistant)
                    .frame(minWidth: stacked ? nil : LockedLayout.chatMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                if !stacked {
                    separator(stacked: false)
                    sideInfo(engine: model.engine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lockBackground)
        .sheet(isPresented: $isShowingMirror) {
            MirrorSheet(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tofuRequestEnd)) { _ in
            endTapped()
        }
    }

    // MARK: Session info

    /// Right pane beside the chat: subject, timer, goal progress, counters and End, top to bottom.
    private func sideInfo(engine: SessionEngine) -> some View {
        let contentWidth = LockedLayout.sidePaneWidth - 2 * Theme.Space.l
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            subjectCaption(engine: engine)
            timerText(engine: engine, width: contentWidth)
            breakLine(engine: engine)
            goalBlock(engine: engine, barWidth: nil)
            countersText(engine: engine)
            Spacer(minLength: Theme.Space.m)
            endButton
        }
        .padding(Theme.Space.l)
        .frame(width: LockedLayout.sidePaneWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Narrow window: the same information as a compact band above the chat.
    private func stackedInfo(engine: SessionEngine, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                subjectCaption(engine: engine)
                timerText(engine: engine, width: max(0, width / 2 - Theme.Space.m))
                breakLine(engine: engine)
                goalBlock(engine: engine, barWidth: 160)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.s) {
                countersText(engine: engine)
                endButton
            }
        }
        .padding(Theme.Space.m)
    }

    private func separator(stacked: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
    }

    private func subjectCaption(engine: SessionEngine) -> some View {
        Text(engine.session?.subjectName ?? "")
            .font(Theme.captionFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func timerText(engine: SessionEngine, width: CGFloat) -> some View {
        Text(TimeFormat.clockFull(engine.remaining ?? engine.elapsed))
            .font(Theme.timerFont(size: LockedLayout.sideTimerFontSize(paneWidth: width)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// Goal progress line and "goal 50m" caption, only in goal mode. `barWidth` nil = as wide as the pane.
    @ViewBuilder private func goalBlock(engine: SessionEngine, barWidth: CGFloat?) -> some View {
        if let goal = engine.session?.mode.goalSeconds {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: barWidth, height: 2)
                    .frame(maxWidth: barWidth == nil ? .infinity : nil)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: bar.size.width * LockedLayout.progress(elapsed: engine.elapsed, goal: goal))
                        }
                    }
                Text(LockedLayout.goalCaption(goalSeconds: goal))
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countersText(engine: SessionEngine) -> some View {
        Text(LockedLayout.countersText(blocked: engine.session?.blockedAttempts ?? 0,
                                       tabs: engine.session?.closedTabs ?? 0))
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var endButton: some View {
        Button("End") { endTapped() }
            .buttonStyle(SecondaryButtonStyle())
    }

    @ViewBuilder private func breakLine(engine: SessionEngine) -> some View {
        if let remaining = engine.breakRemaining {
            Text("Break \(TimeFormat.clockFull(remaining))")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("End break") { engine.endBreak() }
                .buttonStyle(SecondaryButtonStyle())
        } else if engine.canTakeBreak {
            Button("Take a break") { _ = engine.beginBreak(minutes: MirrorTurn.breakDefault) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// End always opens the Mirror. The session stops only if they confirm a stop there.
    /// Shared by the End button and the mini timer's ✕.
    private func endTapped() {
        isShowingMirror = true
    }
}
