import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the mini timer's ✕: LockedView answers by starting the end flow (give-up sheet or confirmation).
    static let tofuRequestEnd = Notification.Name("tofu.requestEnd")
}

/// Pure geometry for the floating mini timer (unit-tested).
enum MiniTimerLayout {
    static let panelSize = CGSize(width: 240, height: 64)
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

    /// How far the pointer moved downward. Cocoa y grows upward, so a downward drag is positive.
    static func pullDown(from start: CGPoint, to current: CGPoint) -> CGFloat {
        start.y - current.y
    }

    /// The pill has gone past the top of `visible` (the edge just under the menu bar). Only the top edge counts.
    static func crossedTop(origin: CGPoint, height: CGFloat, visible: CGRect) -> Bool {
        origin.y + height > visible.maxY
    }

    /// Keeps a bar of `width` inside `visible`. A bar wider than the screen stays on the left edge.
    static func clampedX(_ x: CGFloat, width: CGFloat, visible: CGRect) -> CGFloat {
        let minX = visible.minX
        let maxX = visible.maxX - width
        return min(max(x, minX), max(minX, maxX))
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

    /// Where a press ends. A drag past the top edge tucks. A drag of the tab opens only after `untuckDistance`.
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
            if crossedTop(origin: origin, height: size.height, visible: visible) {
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
}

/// Rounded black/white (inverted in dark mode) pill: subject, timer and a small ✕ (End).
/// Tucked, it is only the time. Clicks and drags are handled by the panel's overlay view.
struct MiniTimerView: View {
    let engine: SessionEngine
    let chrome: MiniTimerChrome

    private var clock: String {
        if let remaining = engine.breakRemaining { return TimeFormat.clock(remaining) }
        return TimeFormat.clock(engine.remaining ?? engine.elapsed)
    }

    private var caption: String {
        engine.isOnBreak ? "Break" : (engine.session?.subjectName ?? "")
    }

    private var progress: Double {
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
        if let name = engine.session?.subjectName {
            return Theme.subjectColor(SubjectColor.hex(for: name))
        }
        return Color.accentColor
    }

    var body: some View {
        Group {
            if chrome.isTucked {
                Text(clock)
                    .font(Theme.timerFont(size: 13))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                .opacity(0.85)
                        }
                        Text(clock)
                            .font(Theme.timerFont(size: 28))
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: MiniTimerLayout.closeButtonSize, height: MiniTimerLayout.closeButtonSize)
                        .overlay(Circle().stroke(Color.lockBackground.opacity(0.5), lineWidth: 1))
                }
                .padding(.horizontal, MiniTimerLayout.horizontalPadding)
            }
        }
        .foregroundStyle(Color.lockBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: chrome.isTucked ? 8 : Theme.radius).fill(Color.primary))
        .overlay(alignment: .bottom) {
            if !chrome.isTucked {
                GeometryReader { geo in
                    Rectangle()
                        .fill(subjectColor)
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                }
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
        }
    }
}

/// Transparent view on top of the SwiftUI content. The panel decides what a press, drag, and release mean.
/// Handling the mouse here (instead of SwiftUI buttons plus isMovableByWindowBackground) keeps a drag
/// from also counting as a click, and works on the first click while the app is inactive.
@MainActor private final class ClickDragView: NSView {
    var onPress: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: ((CGPoint, Bool) -> Void)?
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
        pressMouse = nil
        isDragging = false
        onRelease?(point, dragging)
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

    init(engine: SessionEngine, onOpen: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onEnd = onEnd
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
        let hosting = NSHostingView(rootView: MiniTimerView(engine: engine, chrome: chrome))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let overlay = ClickDragView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onPress = { [weak self] in self?.pointerPressed() }
        overlay.onDrag = { [weak self] mouse in self?.pointerDragged(to: mouse) }
        overlay.onRelease = { [weak self] point, dragging in self?.pointerReleased(at: point, dragging: dragging) }
        container.addSubview(overlay)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the panel top-center on the main screen and shows it without activating the app.
    /// The full pill stays up for `visibleBeforeTuck`, then tucks to the top unless it has been dragged away.
    func show() {
        staysOpen = false
        tuckAfterRelease = false
        chrome.isTucked = false
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
            return
        }
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

    private func pointerReleased(at point: CGPoint, dragging: Bool) {
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
            if MiniTimerLayout.isAwayFromTop(frame: frame, visible: visible) { keepOpen() }
        case .tuck(let frame):
            settle(tucked: true, frame: frame)
        case .reveal(let frame):
            keepOpen()
            settle(tucked: false, frame: frame)
        case .open:
            onOpen()
        case .end:
            onEnd()
        }
        finishRelease()
    }

    /// The user parked the pill below the top, so the automatic tuck leaves it there.
    private func keepOpen() {
        staysOpen = true
        tuckAfterRelease = false
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Hides the pill if the stay already elapsed while it was being held and it was not dragged away.
    private func finishRelease() {
        guard tuckAfterRelease else { return }
        tuckAfterRelease = false
        hideAtTop()
    }

    /// A click that could not find a screen. The tucked tab still opens; the pill still ends or opens the chat.
    private func click(at point: CGPoint) {
        if chrome.isTucked { return }
        if MiniTimerLayout.isCloseHit(point, in: frame.size) { onEnd() } else { onOpen() }
    }

    private func settle(tucked: Bool, frame: CGRect) {
        chrome.isTucked = tucked
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }
    }

    /// The visible frame of the screen under `point`, else the screen the panel is on.
    private func visibleFrame(near point: CGPoint) -> CGRect? {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen.visibleFrame
        }
        return screen?.visibleFrame ?? ScreenGeometry.mainVisibleFrame()
    }
}
