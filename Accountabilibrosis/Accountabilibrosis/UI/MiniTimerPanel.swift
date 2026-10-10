import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the mini timer's ✕: LockedView answers by starting the end flow (give-up sheet or confirmation).
    static let accountabilibrosisRequestEnd = Notification.Name("accountabilibrosis.requestEnd")
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
}

/// Rounded black/white (inverted in dark mode) pill: subject, timer and a small ✕ (End).
/// Purely visual; clicks and drags are handled by the panel's overlay view.
struct MiniTimerView: View {
    let engine: SessionEngine

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.session?.subjectName ?? "")
                    .font(Theme.captionFont)
                    .lineLimit(1)
                    .opacity(0.7)
                Text(TimeFormat.clock(engine.remaining ?? engine.elapsed))
                    .font(Theme.timerFont(size: 28))
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: MiniTimerLayout.closeButtonSize, height: MiniTimerLayout.closeButtonSize)
                .overlay(Circle().stroke(Color.lockBackground.opacity(0.5), lineWidth: 1))
        }
        .foregroundStyle(Color.lockBackground)
        .padding(.horizontal, MiniTimerLayout.horizontalPadding)
        .frame(width: MiniTimerLayout.panelSize.width, height: MiniTimerLayout.panelSize.height)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary))
    }
}

/// Transparent view on top of the SwiftUI content: a click calls `onClick` (or `onClose` when it lands on
/// the ✕), a drag moves the window.
/// Handling the mouse here (instead of SwiftUI buttons plus isMovableByWindowBackground) keeps a drag
/// from also counting as a click, and works on the first click while the app is inactive.
@MainActor private final class ClickDragView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    private var pressMouse: CGPoint?
    private var pressOrigin: CGPoint = .zero
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressMouse = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressMouse, let window else { return }
        let mouse = NSEvent.mouseLocation
        if !isDragging {
            isDragging = MiniTimerLayout.isDrag(from: start, to: mouse)
        }
        if isDragging {
            window.setFrameOrigin(MiniTimerLayout.draggedOrigin(pressOrigin, from: start, to: mouse))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = pressMouse != nil && !isDragging
        pressMouse = nil
        isDragging = false
        guard wasClick else { return }
        let point = convert(event.locationInWindow, from: nil)
        if MiniTimerLayout.isCloseHit(point, in: bounds.size) {
            onClose?()
        } else {
            onClick?()
        }
    }
}

/// Floating, non-activating mini timer shown top-center while a split/full session runs.
/// Clicking the body calls `onOpen` (main window with LockedView); clicking the ✕ calls `onEnd`
/// (main window plus the end flow).
@MainActor final class MiniTimerPanel: NSPanel {
    init(engine: SessionEngine, onOpen: @escaping () -> Void, onEnd: @escaping () -> Void) {
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
        let hosting = NSHostingView(rootView: MiniTimerView(engine: engine))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let overlay = ClickDragView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onClick = onOpen
        overlay.onClose = onEnd
        container.addSubview(overlay)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the panel top-center on the main screen and shows it without activating the app.
    func show() {
        if let visible = ScreenGeometry.mainVisibleFrame() {
            setFrame(MiniTimerLayout.frame(size: MiniTimerLayout.panelSize, visible: visible), display: true)
        } else {
            center()
        }
        orderFrontRegardless()
    }
}
