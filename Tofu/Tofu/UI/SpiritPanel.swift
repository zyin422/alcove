import AppKit
import SwiftUI

/// Why the spirit is moving or speaking. The engine reports these; the panel decides how it looks.
enum SpiritNotice: Equatable {
    case tabClosed(String)
    case appHidden(String)
    case question(host: String, title: String)
}

/// How the circle is moving. Drift is the resting glide. Bounce and roll are short reactions.
enum SpiritMood: Equatable {
    case drift
    case bounce
    case roll
}

/// Pure geometry and lines for the floating circle (unit-tested).
enum SpiritLayout {
    /// Small enough to carry the clock without covering the work. The card is only for a message.
    static let restSize = CGSize(width: 52, height: 52)
    static let expandedSize = CGSize(width: 248, height: 96)
    /// One lap along the top of the screen.
    static let patrolPeriod: TimeInterval = 4.5
    /// How far either side of center the resting circle travels.
    static let patrolTravel: CGFloat = 160

    /// Smoothstep. Slow at both ends, fastest through the middle, so a move accelerates and then settles.
    static func ease(_ t: CGFloat) -> CGFloat {
        let t = min(1, max(0, t))
        return t * t * (3 - 2 * t)
    }

    /// 0 at the left of a lap, 1 at the right, then back. `time` is seconds since the drift started.
    static func patrolProgress(_ time: TimeInterval) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: patrolPeriod) / patrolPeriod
        let ping = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5
        return ease(CGFloat(ping))
    }

    /// The small circle gliding under the menu bar. It is the timer, so it stays on screen while it drifts.
    static func patrolFrame(at time: TimeInterval, visible: CGRect) -> CGRect {
        let travel = min(patrolTravel, max(0, visible.width / 2 - restSize.width))
        let x = visible.midX + (patrolProgress(time) * 2 - 1) * travel - restSize.width / 2
        let y = visible.maxY - MiniTimerLayout.topMargin - restSize.height
        return clamped(CGRect(x: x, y: y, width: restSize.width, height: restSize.height), in: visible)
    }

    /// The spirit on the top edge of an Arc or Chrome window. `quartzWindow` is a window-list frame
    /// (origin at the top-left, y growing down). `primaryHeight` flips that into Cocoa coordinates.
    static func visitFrame(quartzWindow: CGRect, primaryHeight: CGFloat, visible: CGRect) -> CGRect {
        let cocoaTop = primaryHeight - quartzWindow.minY
        let x = quartzWindow.midX - restSize.width / 2
        let y = cocoaTop - restSize.height * 0.45
        return clamped(CGRect(x: x, y: y, width: restSize.width, height: restSize.height), in: visible)
    }

    /// Grows downward from the circle so the text stays on screen when the spirit is near the menu bar.
    static func expandedFrame(around small: CGRect, visible: CGRect) -> CGRect {
        let x = small.midX - expandedSize.width / 2
        let y = small.maxY - expandedSize.height
        return clamped(CGRect(x: x, y: y, width: expandedSize.width, height: expandedSize.height), in: visible)
    }

    static func lerp(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        let t = ease(t)
        return CGRect(x: from.minX + (to.minX - from.minX) * t,
                      y: from.minY + (to.minY - from.minY) * t,
                      width: from.width + (to.width - from.width) * t,
                      height: from.height + (to.height - from.height) * t)
    }

    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        let y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// Goal progress from 0 to 1. If goal is nil or <= 0, cycles through a 25-minute Pomodoro wave.
    static func progress(elapsed: TimeInterval, goal: TimeInterval?) -> Double {
        if let goal, goal > 0 {
            return min(1.0, max(0.0, elapsed / goal))
        }
        let cycle: TimeInterval = 25 * 60
        guard cycle > 0 else { return 0 }
        return (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
    }
}

/// Short lines the spirit says. The same host always gets the same line, and different hosts rotate the pool.
enum SpiritLines {
    static func closedTab(_ host: String) -> String {
        let lines = [
            "I put \(host) away.",
            "\(host) isn't this work. It's closed.",
            "Back to it — \(host) can wait.",
        ]
        return lines[slot(host, count: lines.count)]
    }

    static func appHidden(_ name: String) -> String {
        let lines = [
            "\(name) isn't part of this block.",
            "I set \(name) aside.",
            "Back to the work — \(name) can wait.",
        ]
        return lines[slot(name, count: lines.count)]
    }

    static func question(host: String, title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Does \(host) help with this?" }
        return "Does \(host) help? \(title)"
    }

    static func slot(_ seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % count
    }
}

@Observable @MainActor final class SpiritChrome {
    var mood: SpiritMood = .drift
    var expanded = false
    var text = ""
    /// Bumped to replay a bounce or a roll.
    var bounce = 0
    var spin = 0
}

/// The circle. While it is only keeping time it stays small. A message grows it.
struct SpiritView: View {
    let engine: SessionEngine
    let chrome: SpiritChrome

    private var clock: String {
        if let remaining = engine.breakRemaining { return TimeFormat.clock(remaining) }
        return TimeFormat.clock(engine.remaining ?? engine.elapsed)
    }

    private var progress: Double {
        if let breakRem = engine.breakRemaining, let breakTotal = engine.breakTotal, breakTotal > 0 {
            return min(1.0, max(0.0, 1.0 - (breakRem / breakTotal)))
        }
        return SpiritLayout.progress(elapsed: engine.elapsed, goal: engine.session?.mode.goalSeconds)
    }

    private var isDeepWork: Bool {
        engine.elapsed >= 25 * 60
    }

    private var glowColor: Color {
        if engine.isOnBreak { return Color.orange }
        if isDeepWork { return Color.accentColor }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if chrome.expanded { circle }
            if chrome.expanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clock)
                        .font(Theme.timerFont(size: 18))
                        .lineLimit(1)
                    Text(chrome.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 1) {
                    Text(clock)
                        .font(Theme.timerFont(size: 11))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if isDeepWork || engine.isOnBreak {
                        Circle()
                            .fill(engine.isOnBreak ? Color.orange : Color.lockBackground.opacity(0.85))
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .padding(chrome.expanded ? Theme.Space.s : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.lockBackground)
        .background(RoundedRectangle(cornerRadius: chrome.expanded ? 28 : 26).fill(Color.primary))
        .overlay {
            if !chrome.expanded {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(engine.isOnBreak ? Color.orange : (isDeepWork ? Color.accentColor : Color.primary),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)
            }
        }
        .shadow(color: !chrome.expanded ? glowColor.opacity(0.4) : .clear,
                radius: 8, x: 0, y: 0)
        .overlay(alignment: .topTrailing) {
            if chrome.expanded {
                Text("×")
                    .font(.system(size: 16, weight: .medium))
                    .padding(8)
            }
        }
        .scaleEffect(!chrome.expanded && chrome.bounce % 2 == 1 ? 1.15 : 1)
        .rotationEffect(!chrome.expanded ? .degrees(Double(chrome.spin) * 360) : .zero)
        .animation(.spring(response: 0.32, dampingFraction: 0.42), value: chrome.bounce)
        .animation(.easeInOut(duration: 0.6), value: chrome.spin)
    }

    private var circle: some View {
        Circle()
            .fill(Color.lockBackground.opacity(0.92))
            .frame(width: chrome.expanded ? 28 : 14, height: chrome.expanded ? 28 : 14)
            .scaleEffect(chrome.bounce % 2 == 1 ? 1.28 : 1)
            .rotationEffect(.degrees(Double(chrome.spin) * 360))
            .animation(.spring(response: 0.32, dampingFraction: 0.42), value: chrome.bounce)
            .animation(.easeInOut(duration: 0.6), value: chrome.spin)
    }
}

/// A small circle that keeps the lock-in time and, when something needs the user, glides over to say so.
@MainActor final class SpiritPanel: NSPanel {
    private let chrome = SpiritChrome()
    private let onOpen: () -> Void
    private let onEnd: () -> Void
    /// A circle that only appears to speak hides again once the message is over.
    var hidesWhenQuiet = false
    private var linger: Timer?
    private var ticker: Timer?
    private var generation = 0
    private var drifting = false
    private var driftStarted = CACurrentMediaTime()
    private var flight: Flight?

    private struct Flight {
        var from: CGRect
        var to: CGRect
        var started: TimeInterval
        var duration: TimeInterval
        var then: () -> Void
    }

    init(engine: SessionEngine, onOpen: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onEnd = onEnd
        super.init(contentRect: NSRect(origin: .zero, size: SpiritLayout.restSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let host = NSHostingView(rootView: SpiritView(engine: engine, chrome: chrome))
        let click = SpiritClickView(frame: host.bounds)
        click.autoresizingMask = [.width, .height]
        click.onClick = { [weak self] point in self?.clicked(at: point) }
        host.addSubview(click)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The resting timer: a small circle that glides along the top of the screen.
    func showDrifting() {
        generation += 1
        linger?.invalidate()
        chrome.expanded = false
        chrome.text = ""
        chrome.mood = .drift
        hidesWhenQuiet = false
        drifting = true
        driftStarted = CACurrentMediaTime()
        startTicker()
        orderFrontRegardless()
    }

    func hideSpirit() {
        generation += 1
        linger?.invalidate()
        ticker?.invalidate()
        ticker = nil
        flight = nil
        drifting = false
        orderOut(nil)
    }

    /// Glides to the top of `quartzWindow` when one is known, grows, and says `text`.
    /// `linger` nil keeps it large until the next cue or a click.
    func approach(quartzWindow: CGRect?, text: String, mood: SpiritMood, linger seconds: TimeInterval?) {
        generation += 1
        let token = generation
        linger?.invalidate()
        drifting = false
        play(mood)
        startTicker()
        orderFrontRegardless()
        let visible = ScreenGeometry.mainVisibleFrame()
        let small: CGRect
        if let quartzWindow, let visible, let height = Self.primaryHeight {
            small = SpiritLayout.visitFrame(quartzWindow: quartzWindow, primaryHeight: height, visible: visible)
        } else if let visible {
            small = SpiritLayout.patrolFrame(at: 0, visible: visible)
        } else {
            small = frame
        }
        fly(to: small, duration: 0.7) { [weak self] in
            guard let self, self.generation == token else { return }
            self.expand(text: text, around: small, linger: seconds, token: token)
        }
    }

    private func expand(text: String, around small: CGRect, linger seconds: TimeInterval?, token: Int) {
        chrome.text = text
        chrome.expanded = true
        chrome.mood = .drift
        let destination: CGRect
        if let visible = ScreenGeometry.mainVisibleFrame() {
            destination = SpiritLayout.expandedFrame(around: small, visible: visible)
        } else {
            destination = CGRect(origin: small.origin, size: SpiritLayout.expandedSize)
        }
        fly(to: destination, duration: 0.4) { [weak self] in
            guard let self, self.generation == token, let seconds else { return }
            let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return }
                    self.contract()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.linger = timer
        }
    }

    private func contract() {
        chrome.expanded = false
        chrome.text = ""
        chrome.mood = .drift
        let token = generation
        let small = CGRect(x: frame.midX - SpiritLayout.restSize.width / 2,
                           y: frame.maxY - SpiritLayout.restSize.height,
                           width: SpiritLayout.restSize.width,
                           height: SpiritLayout.restSize.height)
        fly(to: small, duration: 0.45) { [weak self] in
            guard let self, self.generation == token else { return }
            if self.hidesWhenQuiet {
                self.hideSpirit()
            } else {
                self.drifting = true
                self.driftStarted = CACurrentMediaTime()
            }
        }
    }

    private func clicked(at point: CGPoint) {
        if chrome.expanded, point.x > frame.width - 36 {
            onEnd()
            return
        }
        onOpen()
        if chrome.expanded || hidesWhenQuiet { contract() }
        else { play(.bounce) }
    }

    /// Bounce and roll play once, then the circle goes back to drifting.
    private func play(_ mood: SpiritMood) {
        switch mood {
        case .bounce:
            chrome.mood = .bounce
            chrome.bounce += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self else { return }
                self.chrome.bounce += 1
                if self.chrome.mood == .bounce { self.chrome.mood = .drift }
            }
        case .roll:
            chrome.mood = .roll
            chrome.spin += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.chrome.mood == .roll else { return }
                self.chrome.mood = .drift
            }
        case .drift:
            chrome.mood = .drift
        }
    }

    private func fly(to destination: CGRect, duration: TimeInterval, then: @escaping () -> Void) {
        flight = Flight(from: frame, to: destination, started: CACurrentMediaTime(), duration: duration, then: then)
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let flight {
            let raw = flight.duration > 0 ? (now - flight.started) / flight.duration : 1
            if raw >= 1 {
                setFrame(flight.to, display: true)
                let then = flight.then
                self.flight = nil
                then()
            } else {
                setFrame(SpiritLayout.lerp(flight.from, flight.to, CGFloat(raw)), display: true)
            }
            return
        }
        guard drifting, let visible = ScreenGeometry.mainVisibleFrame() else { return }
        setFrame(SpiritLayout.patrolFrame(at: now - driftStarted, visible: visible), display: false)
    }

    private static var primaryHeight: CGFloat? {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? NSScreen.screens.first?.frame.height
    }
}

@MainActor private final class SpiritClickView: NSView {
    var onClick: ((CGPoint) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
}
