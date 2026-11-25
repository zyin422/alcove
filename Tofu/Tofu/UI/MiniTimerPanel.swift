import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the mini timer's ✕: LockedView answers by starting the end flow (give-up sheet or confirmation).
    static let tofuRequestEnd = Notification.Name("tofu.requestEnd")
    /// Posted when user wants to park a thought from the mini timer.
    static let tofuShowThoughts = Notification.Name("tofu.showThoughts")
}

/// Pure geometry for the floating mini timer (unit-tested).
enum MiniTimerLayout {
    static let panelSize = CGSize(width: 296, height: 64)
    /// Gap between the top of the visible frame (below the menu bar) and the panel.
    static let topMargin: CGFloat = 8
    /// Pointer travel (points) after which a press counts as a drag instead of a click.
    static let dragThreshold: CGFloat = 3
    /// Leading/trailing inset of the pill's content; the ✕ sits against the trailing one.
    static let horizontalPadding: CGFloat = Theme.Space.m
    /// Diameter of the ✕ button.
    static let closeButtonSize: CGFloat = 22
    /// Extra clickable margin around the ✕ so the small target is easy to hit.
    static let closeHitSlop: CGFloat = 8

    /// Panel frame centered horizontally at the top of `visible` (Cocoa coordinates), `topMargin` below
    /// its top edge. x is rounded down to whole points; a panel wider than `visible` is pinned to its left edge.
    static func frame(size: CGSize, visible: CGRect, topMargin: CGFloat = MiniTimerLayout.topMargin) -> CGRect {
        let x = visible.minX + max(0, ((visible.width - size.width) / 2).rounded(.down))
        let y = visible.maxY - topMargin - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Clickable area of the ✕ in a panel of `size` (view coordinates): the trailing, vertically centered
    /// button grown by `closeHitSlop` on every side.
    static func closeHitRect(in size: CGSize) -> CGRect {
        let side = closeButtonSize + 2 * closeHitSlop
        return CGRect(x: size.width - horizontalPadding - closeButtonSize - closeHitSlop,
                      y: (size.height - side) / 2,
                      width: side, height: side)
    }

    /// True when `point` (view coordinates) lands on the ✕ rather than the body.
    static func isCloseHit(_ point: CGPoint, in size: CGSize) -> Bool {
        closeHitRect(in: size).contains(point)
    }

    /// Clickable area of the thought parking button immediately to the left of the ✕.
    static func thoughtHitRect(in size: CGSize) -> CGRect {
        let side = closeButtonSize + 2 * closeHitSlop
        let closeRect = closeHitRect(in: size)
        return CGRect(x: closeRect.minX - side, y: closeRect.minY, width: side, height: side)
    }

    /// True when `point` (view coordinates) lands on the thought parking button.
    static func isThoughtHit(_ point: CGPoint, in size: CGSize) -> Bool {
        thoughtHitRect(in: size).contains(point)
    }

    /// Clickable area of the soundscape button immediately to the left of thought button.
    static func soundHitRect(in size: CGSize) -> CGRect {
        let side = closeButtonSize + 2 * closeHitSlop
        let thoughtRect = thoughtHitRect(in: size)
        return CGRect(x: thoughtRect.minX - side, y: thoughtRect.minY, width: side, height: side)
    }

    /// True when `point` (view coordinates) lands on the soundscape quick-cycle button.
    static func isSoundHit(_ point: CGPoint, in size: CGSize) -> Bool {
        soundHitRect(in: size).contains(point)
    }

    /// Number of completed 25-minute focus cycles in an open-ended session.
    static func completedFlowCycles(elapsed: TimeInterval, cycleLength: TimeInterval = 25 * 60) -> Int {
        guard elapsed >= cycleLength, cycleLength > 0 else { return 0 }
        return Int(elapsed / cycleLength)
    }

    /// Clickable area of the trailing Lock In button shown between blocks.
    static func lockInHitRect(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 100, y: 0, width: 100, height: size.height)
    }

    /// True when `point` (view coordinates) lands on the trailing Lock In button.
    static func isLockInHit(_ point: CGPoint, in size: CGSize) -> Bool {
        lockInHitRect(in: size).contains(point)
    }

    /// Clickable area of the trailing Resume button shown during breaks.
    static func resumeHitRect(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 66, y: 0, width: 66, height: size.height)
    }

    /// True when `point` (view coordinates) lands on the trailing Resume button.
    static func isResumeHit(_ point: CGPoint, in size: CGSize) -> Bool {
        resumeHitRect(in: size).contains(point)
    }

    /// Clickable area of the trailing +2m break extend button shown during breaks.
    static func extendBreakHitRect(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 114, y: 0, width: 46, height: size.height)
    }

    /// True when `point` (view coordinates) lands on the +2m break extend button.
    static func isExtendBreakHit(_ point: CGPoint, in size: CGSize) -> Bool {
        extendBreakHitRect(in: size).contains(point)
    }

    /// True once the pointer is at least `dragThreshold` points away from where the press began.
    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    /// Panel origin after the pointer moved from `mouseStart` to `mouse` (screen coordinates).
    static func draggedOrigin(_ origin: CGPoint, from mouseStart: CGPoint, to mouse: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (mouse.x - mouseStart.x), y: origin.y + (mouse.y - mouseStart.y))
    }

    /// Height of the tab left at the top edge. Wide enough for "H:MM:SS".
    static let tabSize = CGSize(width: 88, height: 22)
    /// Downward pull (points) after which letting go of the tab opens the pill.
    static let untuckDistance: CGFloat = 24
    /// How long the full pill stays up when a block starts, before it tucks to the top on its own.
    static let visibleBeforeTuck: TimeInterval = 3
    /// Distance from the top edge (below menu bar) within which releasing snaps and tucks into the menu bar tab.
    static let topSnapThreshold: CGFloat = 80

    /// How far the pointer moved downward. Cocoa y grows upward, so a downward drag is positive.
    static func pullDown(from start: CGPoint, to current: CGPoint) -> CGFloat {
        start.y - current.y
    }

    /// The pill has gone past the top of `visible` (the edge just under the menu bar). Only the top edge counts.
    static func crossedTop(origin: CGPoint, height: CGFloat, visible: CGRect) -> Bool {
        origin.y + height > visible.maxY
    }

    /// True when the panel is at or near the top edge of `visible` (within `topSnapThreshold` or crossing it).
    static func isNearTop(origin: CGPoint, height: CGFloat, visible: CGRect) -> Bool {
        origin.y + height >= visible.maxY - topMargin - topSnapThreshold
    }

    /// True when `origin` lies within any connected screen frame.
    static func isPositionOnAnyScreen(_ origin: CGPoint, in screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { $0.contains(origin) }
    }

    /// Keeps a bar of `width` inside `visible`. A bar wider than the screen stays on the left edge.
    static func clampedX(_ x: CGFloat, width: CGFloat, visible: CGRect) -> CGFloat {
        let minX = visible.minX
        let maxX = visible.maxX - width
        return min(max(x, minX), max(minX, maxX))
    }

    /// Finds the visible frame of the screen containing `point`, or falls back to provided screen.
    static func targetScreenVisible(point: CGPoint, screens: [CGRect], visibleFrames: [CGRect], fallback: CGRect) -> CGRect {
        for (index, frame) in screens.enumerated() {
            if frame.contains(point) && index < visibleFrames.count {
                return visibleFrames[index]
            }
        }
        // If cursor is thrown into menu bar or slightly outside screen bounds, find screen with closest midpoint
        if let closestIndex = screens.indices.min(by: { i1, i2 in
            let f1 = screens[i1], f2 = screens[i2]
            return hypot(f1.midX - point.x, f1.midY - point.y) < hypot(f2.midX - point.x, f2.midY - point.y)
        }), closestIndex < visibleFrames.count {
            return visibleFrames[closestIndex]
        }
        return fallback
    }

    /// The tab at the top edge, centered on `centerX`.
    static func tuckedFrame(centerX: CGFloat, visible: CGRect) -> CGRect {
        let x = clampedX(centerX - tabSize.width / 2, width: tabSize.width, visible: visible)
        return CGRect(x: x, y: visible.maxY - tabSize.height, width: tabSize.width, height: tabSize.height)
    }

    /// True when an open pill sits at least `untuckDistance` below where it rests under the menu bar.
    static func isAwayFromTop(frame: CGRect, visible: CGRect) -> Bool {
        let restingTop = visible.maxY - topMargin
        return frame.maxY <= restingTop - untuckDistance
    }

    /// The full pill just under the menu bar, centered on `centerX`.
    static func revealedFrame(centerX: CGFloat, visible: CGRect) -> CGRect {
        let x = clampedX(centerX - panelSize.width / 2, width: panelSize.width, visible: visible)
        return CGRect(x: x, y: visible.maxY - topMargin - panelSize.height,
                      width: panelSize.width, height: panelSize.height)
    }

    /// Full pill while the tucked tab is being pulled down. Its top tracks the pointer; its center tracks `centerX`.
    static func pullingFrame(centerX: CGFloat, pullDown: CGFloat, visible: CGRect) -> CGRect {
        let x = clampedX(centerX - panelSize.width / 2, width: panelSize.width, visible: visible)
        let top = visible.maxY - max(0, pullDown)
        return CGRect(x: x, y: top - panelSize.height, width: panelSize.width, height: panelSize.height)
    }

    /// What a drag does to the window before it is released. An open pill follows the pointer, even above the
    /// screen. A tucked tab stays a tab until it is pulled downward, and then the pill follows.
    static func frameDuringDrag(tucked: Bool, pressOrigin: CGPoint, pressSize: CGSize,
                                pressMouse: CGPoint, mouse: CGPoint, visible: CGRect) -> CGRect {
        let moved = draggedOrigin(pressOrigin, from: pressMouse, to: mouse)
        let centerX = moved.x + pressSize.width / 2
        let pull = pullDown(from: pressMouse, to: mouse)
        if tucked, pull > 0 {
            return pullingFrame(centerX: centerX, pullDown: pull, visible: visible)
        }
        if tucked {
            return tuckedFrame(centerX: centerX, visible: visible)
        }
        return CGRect(origin: moved, size: panelSize)
    }

    /// Where a press ends. A drag near or past the top edge tucks. A drag of the tab opens only after `untuckDistance`.
    /// A click on the tab leaves it tucked. A click on the pill opens the chat, and a click on the ✕ ends the session.
    static func release(tucked: Bool, dragging: Bool, origin: CGPoint, size: CGSize,
                        pullDown: CGFloat, closeHit: Bool, visible: CGRect) -> MiniTimerRelease {
        let centerX = origin.x + size.width / 2
        if dragging {
            if tucked {
                return pullDown >= untuckDistance
                    ? .reveal(revealedFrame(centerX: centerX, visible: visible))
                    : .tuck(tuckedFrame(centerX: centerX, visible: visible))
            }
            if isNearTop(origin: origin, height: size.height, visible: visible) {
                return .tuck(tuckedFrame(centerX: centerX, visible: visible))
            }
            return .leave
        }
        if tucked { return .leave }
        return closeHit ? .end : .open
    }
}

/// Result of letting go of the mini timer.
enum MiniTimerRelease: Equatable {
    /// The drag ended short of the top edge; the pill stays where it was dropped.
    case leave
    case tuck(CGRect)
    case reveal(CGRect)
    /// A click on the open pill: show the chat.
    case open
    /// A click on the ✕: end the session.
    case end
}

/// Whether the floating timer is the full pill or the tab left at the top edge.
@Observable @MainActor final class MiniTimerChrome {
    var isTucked = false
    var noticeText: String?
}

/// Rounded floating HUD pill: subject, timer, parked thought launcher, and a small ✕ (End).
/// Tucked, it is only the time with a luminous glowing status pip. Clicks and drags are handled by the panel's overlay view.
struct MiniTimerView: View {
    let engine: SessionEngine
    let chrome: MiniTimerChrome
    var model: AppModel? = nil
    var onLockIn: (() -> Void)? = nil

    private var isBetweenBlocks: Bool {
        !engine.isLocked && model?.nextForceBlockDeadline != nil
    }

    private func clock(now: Date) -> String {
        if isBetweenBlocks, let deadline = model?.nextForceBlockDeadline {
            let seconds = max(0, deadline.timeIntervalSince(now))
            return TimeFormat.clock(seconds)
        }
        if let remaining = engine.breakRemaining { return TimeFormat.clock(remaining) }
        return TimeFormat.clock(engine.remaining ?? engine.elapsed)
    }

    private var caption: String {
        if isBetweenBlocks {
            return model?.nextForceBlockReason ?? "Force Lock-In"
        }
        if engine.isOnBreak { return "Break" }
        let subName = engine.session?.subjectName ?? ""
        if let model, let session = engine.session {
            let todayKey = DayKey.key(for: Date())
            if let p = model.plan(for: todayKey)?.priorities.first(where: { $0.subjectID == session.subjectID && !$0.isDone }) {
                return "\(subName) · \(p.title)"
            }
        }
        return subName
    }

    private func progress(now: Date) -> Double {
        if isBetweenBlocks, let deadline = model?.nextForceBlockDeadline {
            let total = DayPlanner.betweenBlockGrace
            let remaining = max(0, deadline.timeIntervalSince(now))
            return min(1.0, max(0.0, 1.0 - (remaining / total)))
        }
        if let breakRem = engine.breakRemaining, let breakTotal = engine.breakTotal, breakTotal > 0 {
            return min(1.0, max(0.0, 1.0 - (breakRem / breakTotal)))
        }
        if let goal = engine.session?.mode.goalSeconds, goal > 0 {
            return min(1.0, max(0.0, engine.elapsed / goal))
        }
        let cycle: TimeInterval = 25 * 60
        return (engine.elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
    }

    private var subjectColor: Color {
        if isBetweenBlocks { return Theme.amber }
        if engine.isOnBreak { return Theme.coral }
        if let name = engine.session?.subjectName {
            return Theme.subjectColor(SubjectColor.hex(for: name))
        }
        return Theme.indigo
    }

    @ViewBuilder private var openSessionMilestones: some View {
        if engine.isLocked && engine.session?.mode == .open && !engine.isOnBreak && !engine.isOnGracePass {
            let completedCycles = MiniTimerLayout.completedFlowCycles(elapsed: engine.elapsed)
            if completedCycles > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(completedCycles, 4), id: \.self) { _ in
                        Circle()
                            .fill(subjectColor)
                            .frame(width: 4, height: 4)
                    }
                    if completedCycles > 4 {
                        Text("+\(completedCycles - 4)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(subjectColor)
                    }
                }
                .help("\(completedCycles) × 25m focus blocks completed")
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            content(now: context.date)
        }
    }

    private var pillCornerRadius: CGFloat {
        chrome.isTucked ? 8 : Theme.radius
    }

    private func content(now: Date) -> some View {
        let pillShape = RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)

        return Group {
            if chrome.isTucked {
                HStack(spacing: 5) {
                    Circle()
                        .fill(subjectColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: subjectColor.opacity(0.8), radius: 2)
                    Text(clock(now: now))
                        .font(Theme.timerFont(size: 12))
                        .foregroundStyle(isBetweenBlocks ? Theme.amber : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let notice = chrome.noticeText {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.rose)
                    Text(notice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, MiniTimerLayout.horizontalPadding)
            } else {
                HStack(spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(subjectColor)
                                .frame(width: 6, height: 6)
                            Text(caption)
                                .font(Theme.captionFont)
                                .lineLimit(1)
                                .foregroundStyle(isBetweenBlocks ? Theme.amber : Color.secondary)

                            if engine.deflectionsCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "shield.fill")
                                        .font(.system(size: 7, weight: .bold))
                                    Text("\(engine.deflectionsCount)")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.amber.opacity(0.2)))
                                .foregroundStyle(Theme.amber)
                                .fixedSize()
                                .layoutPriority(1)
                                .help(engine.deflectionsSummary)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(clock(now: now))
                                .font(Theme.timerFont(size: 28))
                                .foregroundStyle(isBetweenBlocks ? Theme.amber : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)

                            openSessionMilestones
                                .fixedSize()
                        }
                    }
                    Spacer(minLength: Theme.Space.s)
                    if isBetweenBlocks {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("LOCK IN")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amber))
                        .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.01))
                        .help("Lock in now")
                    } else if engine.isOnGracePass, let remaining = engine.gracePassRemaining {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 9, weight: .bold))
                            Text("PASS \(TimeFormat.clock(remaining))")
                                .font(.system(size: 9, weight: .bold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amber))
                        .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.01))
                        .help("Emergency grace pass active (click to resume lock-in)")
                    } else if engine.isOnBreak {
                        HStack(spacing: 5) {
                            Text("+2m")
                                .font(.system(size: 9.5, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.coral.opacity(0.18)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.coral.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(Theme.coral)
                                .help("Extend break by 2 minutes (up to 15m)")

                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("RESUME")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5.5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.coral))
                            .foregroundStyle(Color.white)
                            .help("End break and resume focus")
                        }
                    } else {
                        HStack(spacing: 8) {
                            let sound = model?.data.settings.focusSound ?? .off
                            let isSoundActive = sound != .off && FocusAudioEngine.shared.isPlaying
                            Image(systemName: FocusAudioEngine.iconName(for: sound))
                                .font(.system(size: 11))
                                .foregroundStyle(isSoundActive ? Theme.indigo : Color.secondary)
                                .frame(width: MiniTimerLayout.closeButtonSize, height: MiniTimerLayout.closeButtonSize)
                                .background(Circle().fill(isSoundActive ? Theme.indigo.opacity(0.18) : Color.primary.opacity(0.08)))
                                .overlay(
                                    isSoundActive ? Circle().stroke(Theme.indigo.opacity(0.4), lineWidth: 1) : nil
                                )
                                .help(isSoundActive ? "Soundscape: \(sound.rawValue) (click to cycle, ⌥-click to mute)" : "Focus soundscape: Off (click to cycle, ⌥-click to resume)")

                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .frame(width: MiniTimerLayout.closeButtonSize, height: MiniTimerLayout.closeButtonSize)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                                .help("Park stray thought (⌘3)")

                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .frame(width: MiniTimerLayout.closeButtonSize, height: MiniTimerLayout.closeButtonSize)
                                .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                                .help("End session")
                        }
                    }
                }
                .padding(.horizontal, MiniTimerLayout.horizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pillShape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(alignment: .top) {
            if !chrome.isTucked && chrome.noticeText == nil {
                Rectangle()
                    .fill(subjectColor)
                    .frame(height: 2.5)
            }
        }
        .overlay(alignment: .bottom) {
            if !chrome.isTucked && chrome.noticeText == nil {
                GeometryReader { geo in
                    Rectangle()
                        .fill(subjectColor)
                        .frame(width: geo.size.width * CGFloat(progress(now: now)), height: 3)
                }
                .frame(height: 3)
            }
        }
        .clipShape(pillShape)
        .overlay(
            pillShape.strokeBorder(subjectColor.opacity(chrome.isTucked ? 0.35 : 0.5), lineWidth: 1)
        )
    }
}

/// Transparent view on top of the SwiftUI content. The panel decides what a press, drag, and release mean.
/// Handling the mouse here (instead of SwiftUI buttons plus isMovableByWindowBackground) keeps a drag
/// from also counting as a click, and works on the first click while the app is inactive.
@MainActor private final class ClickDragView: NSView {
    var onPress: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: ((CGPoint, Bool, NSEvent.ModifierFlags) -> Void)?
    private var pressMouse: CGPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressMouse = NSEvent.mouseLocation
        isDragging = false
        onPress?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressMouse else { return }
        let mouse = NSEvent.mouseLocation
        if !isDragging {
            isDragging = MiniTimerLayout.isDrag(from: start, to: mouse)
        }
        if isDragging { onDrag?(mouse) }
    }

    override func mouseUp(with event: NSEvent) {
        guard pressMouse != nil else { return }
        let dragging = isDragging
        let point = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags
        pressMouse = nil
        isDragging = false
        onRelease?(point, dragging, flags)
    }
}

/// Floating, non-activating mini timer shown top-center while a split/full session runs.
/// It stays up briefly when a block starts, then tucks into a time tab at the top.
/// Drag the tab down and it stays as the pill; drag the pill past the top edge and it tucks again.
/// Clicking the open pill calls `onOpen` (main window with LockedView); clicking the ✕ calls `onEnd`
/// (main window plus the end flow).
@MainActor final class MiniTimerPanel: NSPanel {
    private let chrome = MiniTimerChrome()
    private let onOpen: () -> Void
    private let onEnd: () -> Void
    private let onLockIn: (() -> Void)?
    private let onParkThought: (() -> Void)?
    private let onCycleSound: (() -> Void)?
    private let onToggleMute: (() -> Void)?
    private let engine: SessionEngine
    private let model: AppModel?
    /// True when the press began on the tucked tab. A drag that starts open can cross the top without this.
    private var pressWasTucked = false
    private var pressOrigin: CGPoint = .zero
    private var pressSize: CGSize = MiniTimerLayout.panelSize
    private var pressMouse: CGPoint = .zero
    /// The user dragged the pill down from the top, so the automatic tuck should not put it back.
    private var staysOpen = false
    /// A press is in progress, so the automatic tuck waits until they let go.
    private var pointerDown = false
    /// The stay-then-hide delay already elapsed during a press.
    private var tuckAfterRelease = false
    private var hideTimer: Timer?

    init(engine: SessionEngine,
         model: AppModel? = nil,
         onOpen: @escaping () -> Void,
         onEnd: @escaping () -> Void,
         onLockIn: (() -> Void)? = nil,
         onParkThought: (() -> Void)? = nil,
         onCycleSound: (() -> Void)? = nil,
         onToggleMute: (() -> Void)? = nil) {
        self.engine = engine
        self.model = model
        self.onOpen = onOpen
        self.onEnd = onEnd
        self.onLockIn = onLockIn
        self.onParkThought = onParkThought
        self.onCycleSound = onCycleSound
        self.onToggleMute = onToggleMute
        let size = MiniTimerLayout.panelSize
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let hosting = NSHostingView(rootView: MiniTimerView(engine: engine, chrome: chrome, model: model, onLockIn: onLockIn))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)

        let overlay = ClickDragView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onPress = { [weak self] in self?.pointerPressed() }
        overlay.onDrag = { [weak self] mouse in self?.pointerDragged(to: mouse) }
        overlay.onRelease = { [weak self] point, dragging, flags in self?.pointerReleased(at: point, dragging: dragging, modifiers: flags) }
        container.addSubview(overlay)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Briefly displays an intervention notice (e.g. closed tab or hidden app) then smoothly tucks back.
    func showNotice(_ text: String) {
        chrome.noticeText = text
        if chrome.isTucked {
            if let visible = screen?.visibleFrame ?? ScreenGeometry.mainVisibleFrame() {
                staysOpen = false
                settle(tucked: false, frame: MiniTimerLayout.revealedFrame(centerX: frame.midX, visible: visible))
            }
        }
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 3.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.chrome.noticeText = nil
                self?.hideAtTop()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    /// Places the panel top-center on the main screen and shows it without activating the app.
    /// The full pill stays up for `visibleBeforeTuck`, then tucks to the top unless it has been dragged away.
    func show() {
        tuckAfterRelease = false
        chrome.isTucked = false

        if UserDefaults.standard.bool(forKey: "miniTimerHasCustomOrigin") {
            let x = CGFloat(UserDefaults.standard.double(forKey: "miniTimerCustomOriginX"))
            let y = CGFloat(UserDefaults.standard.double(forKey: "miniTimerCustomOriginY"))
            let savedOrigin = CGPoint(x: x, y: y)
            let screens = NSScreen.screens.map(\.frame)
            if MiniTimerLayout.isPositionOnAnyScreen(savedOrigin, in: screens) {
                staysOpen = true
                setFrameOrigin(savedOrigin)
                orderFrontRegardless()
                return
            } else {
                clearCustomOrigin()
            }
        }

        staysOpen = false
        if let visible = ScreenGeometry.mainVisibleFrame() {
            setFrame(MiniTimerLayout.frame(size: MiniTimerLayout.panelSize, visible: visible), display: true)
        } else {
            center()
        }
        orderFrontRegardless()
        scheduleHide()
    }

    override func orderOut(_ sender: Any?) {
        hideTimer?.invalidate()
        hideTimer = nil
        super.orderOut(sender)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: MiniTimerLayout.visibleBeforeTuck, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideAtTop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    /// Tucks the pill to the top. Skipped once the user has dragged it away, and deferred while they are holding it.
    private func hideAtTop() {
        hideTimer = nil
        guard !staysOpen, !chrome.isTucked else { return }
        if pointerDown {
            tuckAfterRelease = true
            return
        }
        guard let visible = screen?.visibleFrame ?? ScreenGeometry.mainVisibleFrame() else { return }
        if MiniTimerLayout.isAwayFromTop(frame: frame, visible: visible) {
            staysOpen = true
            saveCustomOrigin(frame.origin)
            return
        }
        clearCustomOrigin()
        settle(tucked: true, frame: MiniTimerLayout.tuckedFrame(centerX: frame.midX, visible: visible))
    }

    private func pointerPressed() {
        pointerDown = true
        pressWasTucked = chrome.isTucked
        pressOrigin = frame.origin
        pressSize = frame.size
        pressMouse = NSEvent.mouseLocation
    }

    private func pointerDragged(to mouse: CGPoint) {
        guard let visible = visibleFrame(near: mouse) else {
            setFrameOrigin(MiniTimerLayout.draggedOrigin(pressOrigin, from: pressMouse, to: mouse))
            return
        }
        let next = MiniTimerLayout.frameDuringDrag(tucked: pressWasTucked, pressOrigin: pressOrigin,
                                                    pressSize: pressSize, pressMouse: pressMouse,
                                                    mouse: mouse, visible: visible)
        chrome.isTucked = pressWasTucked && MiniTimerLayout.pullDown(from: pressMouse, to: mouse) <= 0
        setFrame(next, display: true)
    }

    private func pointerReleased(at point: CGPoint, dragging: Bool, modifiers: NSEvent.ModifierFlags = []) {
        pointerDown = false
        let mouse = NSEvent.mouseLocation
        guard let visible = visibleFrame(near: mouse) else {
            if !dragging { click(at: point) }
            finishRelease()
            return
        }
        let action = MiniTimerLayout.release(tucked: pressWasTucked, dragging: dragging,
                                              origin: frame.origin, size: frame.size,
                                              pullDown: MiniTimerLayout.pullDown(from: pressMouse, to: mouse),
                                              closeHit: MiniTimerLayout.isCloseHit(point, in: frame.size),
                                              visible: visible)
        switch action {
        case .leave:
            if pressWasTucked && !dragging {
                toggleTuck()
            } else if MiniTimerLayout.isAwayFromTop(frame: frame, visible: visible) {
                keepOpen()
            } else {
                staysOpen = false
                hideAtTop()
            }
        case .tuck(let frame):
            staysOpen = false
            hideTimer?.invalidate()
            hideTimer = nil
            settle(tucked: true, frame: frame)
        case .reveal(let frame):
            staysOpen = false
            settle(tucked: false, frame: frame)
            scheduleHide()
        case .open:
            if !engine.isLocked && model?.nextForceBlockDeadline != nil {
                if MiniTimerLayout.isLockInHit(point, in: frame.size) {
                    onLockIn?()
                } else {
                    onOpen()
                }
            } else if engine.isOnGracePass {
                if MiniTimerLayout.isResumeHit(point, in: frame.size) {
                    engine.endGracePass()
                } else {
                    onOpen()
                }
            } else if engine.isOnBreak {
                if MiniTimerLayout.isExtendBreakHit(point, in: frame.size) {
                    engine.extendBreak(minutes: 2)
                } else if MiniTimerLayout.isResumeHit(point, in: frame.size) {
                    engine.endBreak()
                } else {
                    onOpen()
                }
            } else {
                if MiniTimerLayout.isThoughtHit(point, in: frame.size) {
                    onParkThought?()
                } else if MiniTimerLayout.isSoundHit(point, in: frame.size) {
                    if modifiers.contains(.option) {
                        onToggleMute?()
                    } else {
                        onCycleSound?()
                    }
                } else {
                    onOpen()
                }
            }
        case .end:
            if !engine.isLocked && model?.nextForceBlockDeadline != nil {
                onLockIn?()
            } else {
                onEnd()
            }
        }
        finishRelease()
    }

    /// The user parked the pill below the top, so the automatic tuck leaves it there.
    private func keepOpen() {
        staysOpen = true
        tuckAfterRelease = false
        hideTimer?.invalidate()
        hideTimer = nil
        saveCustomOrigin(frame.origin)
    }

    private func saveCustomOrigin(_ origin: CGPoint) {
        UserDefaults.standard.set(Double(origin.x), forKey: "miniTimerCustomOriginX")
        UserDefaults.standard.set(Double(origin.y), forKey: "miniTimerCustomOriginY")
        UserDefaults.standard.set(true, forKey: "miniTimerHasCustomOrigin")
    }

    private func clearCustomOrigin() {
        UserDefaults.standard.removeObject(forKey: "miniTimerHasCustomOrigin")
        UserDefaults.standard.removeObject(forKey: "miniTimerCustomOriginX")
        UserDefaults.standard.removeObject(forKey: "miniTimerCustomOriginY")
    }

    /// Hides the pill if the stay already elapsed while it was being held and it was not dragged away.
    private func finishRelease() {
        if tuckAfterRelease {
            tuckAfterRelease = false
            hideAtTop()
        } else if !chrome.isTucked && !staysOpen {
            scheduleHide()
        }
    }

    /// A click that could not find a screen. The tucked tab still opens; the pill still ends or opens the chat.
    private func click(at point: CGPoint) {
        if chrome.isTucked {
            toggleTuck()
            return
        }
        if !engine.isLocked && model?.nextForceBlockDeadline != nil {
            if MiniTimerLayout.isLockInHit(point, in: frame.size) || MiniTimerLayout.isCloseHit(point, in: frame.size) {
                onLockIn?()
            } else {
                onOpen()
            }
        } else if engine.isOnBreak {
            if MiniTimerLayout.isExtendBreakHit(point, in: frame.size) {
                engine.extendBreak(minutes: 2)
            } else if MiniTimerLayout.isResumeHit(point, in: frame.size) {
                engine.endBreak()
            } else {
                onOpen()
            }
        } else {
            if MiniTimerLayout.isCloseHit(point, in: frame.size) {
                onEnd()
            } else if MiniTimerLayout.isThoughtHit(point, in: frame.size) {
                onParkThought?()
            } else {
                onOpen()
            }
        }
    }

    /// Toggles the floating mini timer between tucked tab and revealed pill.
    func toggleTuck() {
        guard let visible = screen?.visibleFrame ?? ScreenGeometry.mainVisibleFrame() else { return }
        if chrome.isTucked {
            staysOpen = false
            settle(tucked: false, frame: MiniTimerLayout.revealedFrame(centerX: frame.midX, visible: visible))
            scheduleHide()
        } else {
            staysOpen = false
            hideTimer?.invalidate()
            hideTimer = nil
            settle(tucked: true, frame: MiniTimerLayout.tuckedFrame(centerX: frame.midX, visible: visible))
        }
    }

    private func settle(tucked: Bool, frame: CGRect) {
        chrome.isTucked = tucked
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.invalidateShadow() }
        })
    }

    /// The visible frame of the screen under `point`, else the screen the panel is on.
    private func visibleFrame(near point: CGPoint) -> CGRect? {
        let screens = NSScreen.screens.map(\.frame)
        let visible = NSScreen.screens.map(\.visibleFrame)
        let fallback = screen?.visibleFrame ?? ScreenGeometry.mainVisibleFrame() ?? .zero
        return MiniTimerLayout.targetScreenVisible(point: point, screens: screens, visibleFrames: visible, fallback: fallback)
    }
}
