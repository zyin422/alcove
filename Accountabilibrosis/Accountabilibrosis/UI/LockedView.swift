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

    /// Giant timer font size for the space it gets: min(width / 5, height * 0.42), never below 1 pt.
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

/// Giant timer screen shown in the main window while locked: subject, timer, goal progress,
/// counters and the End button. It re-renders every tick because it reads `engine.now`
/// (through `elapsed`/`remaining`). The mini timer's ✕ starts the same end flow as the End button.
struct LockedView: View {
    let model: AppModel
    @State private var isConfirmingEnd = false
    @State private var isShowingGiveUp = false

    var body: some View {
        let engine = model.engine
        VStack(spacing: Theme.Space.l) {
            Text(engine.session?.subjectName ?? "")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { proxy in
                timerBlock(engine: engine, size: proxy.size)
            }

            Text(LockedLayout.countersText(blocked: engine.session?.blockedAttempts ?? 0,
                                           tabs: engine.session?.closedTabs ?? 0))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("End") { endTapped() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lockBackground)
        .confirmationDialog("End this session?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("End session") {
                Task { await model.engine.finish() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your time so far is saved and hidden apps come back.")
        }
        .sheet(isPresented: $isShowingGiveUp) {
            GiveUpSheet(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountabilibrosisRequestEnd)) { _ in
            endTapped()
        }
    }

    /// Timer sized to the available space, plus the goal progress line and caption in goal mode.
    private func timerBlock(engine: SessionEngine, size: CGSize) -> some View {
        VStack(spacing: Theme.Space.m) {
            Text(TimeFormat.clockFull(engine.remaining ?? engine.elapsed))
                .font(Theme.timerFont(size: LockedLayout.timerFontSize(for: size)))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
            if let goal = engine.session?.mode.goalSeconds {
                let barWidth = size.width * 0.6
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.15))
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: barWidth * LockedLayout.progress(elapsed: engine.elapsed, goal: goal))
                }
                .frame(width: barWidth, height: 2)
                Text(LockedLayout.goalCaption(goalSeconds: goal))
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Goal mode before the goal needs the give-up phrase; everything else just confirms.
    /// Shared by the End button and the mini timer's ✕.
    private func endTapped() {
        if model.engine.needsGiveUpPhrase {
            isShowingGiveUp = true
        } else {
            isConfirmingEnd = true
        }
    }
}
