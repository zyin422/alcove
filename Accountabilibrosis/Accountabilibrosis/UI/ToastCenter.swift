import AppKit
import SwiftUI

@MainActor protocol Toasting: AnyObject {
    func show(_ message: String)
}

/// Pure geometry for toasts stacked in the top-right corner of a screen's visible frame.
enum ToastLayout {
    static let toastSize = CGSize(width: 320, height: 56)
    static let gap: CGFloat = 8
    static let margin: CGFloat = 16

    /// Cocoa-coordinate frame of the toast at `index` (0 = top). Each next index sits `gap` points below the previous.
    static func frame(index: Int, size: CGSize, visible: CGRect, margin: CGFloat) -> CGRect {
        let row = CGFloat(max(0, index))
        let top = visible.maxY - margin - row * (size.height + gap)
        return CGRect(x: visible.maxX - margin - size.width, y: top - size.height,
                      width: size.width, height: size.height)
    }
}

/// Monochrome top-right toasts in borderless, non-activating, click-through panels.
/// Newest toast on top; at most `maxVisible` at once (the oldest is dropped); each disappears after `displayDuration`.
@MainActor final class ToastCenter: Toasting {
    static let shared = ToastCenter()
    static let displayDuration: TimeInterval = 3
    static let maxVisible = 3

    private struct Entry {
        let id: UUID
        let panel: NSPanel
    }

    /// Index 0 is the newest toast (drawn on top).
    private var entries: [Entry] = []

    init() {}

    func show(_ message: String) {
        guard let visible = ScreenGeometry.mainVisibleFrame() else { return }
        let entry = Entry(id: UUID(), panel: makePanel(message: message))
        entries.insert(entry, at: 0)
        while entries.count > Self.maxVisible {
            entries.removeLast().panel.orderOut(nil)
        }
        restack(in: visible)
        entry.panel.orderFrontRegardless()

        let id = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            self?.dismiss(id: id)
        }
    }

    private func dismiss(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index).panel.orderOut(nil)
        if let visible = ScreenGeometry.mainVisibleFrame() { restack(in: visible) }
    }

    private func restack(in visible: CGRect) {
        for (index, entry) in entries.enumerated() {
            let frame = ToastLayout.frame(index: index, size: ToastLayout.toastSize,
                                          visible: visible, margin: ToastLayout.margin)
            entry.panel.setFrame(frame, display: true)
        }
    }

    private func makePanel(message: String) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: ToastLayout.toastSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false   // we are usually NOT the active app while locked in
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ToastView(message: message))
        host.sizingOptions = []           // the panel keeps ToastLayout.toastSize
        host.frame = CGRect(origin: .zero, size: ToastLayout.toastSize)
        panel.contentView = host
        return panel
    }
}

/// Inverted pill: primary-colored fill (black in light mode, white in dark) with background-colored text.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary))
    }
}
