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

/// Pure category classification and styling for toast telemetry HUD alerts.
enum ToastCategory: Equatable {
    case shield
    case grace
    case rest
    case completed
    case telemetry

    var tag: String {
        switch self {
        case .shield: "SHIELD INTERVENTION"
        case .grace: "GRACE PASS"
        case .rest: "BREAK RECHARGE"
        case .completed: "SESSION LOGGED"
        case .telemetry: "TOFU TELEMETRY"
        }
    }

    var iconName: String {
        switch self {
        case .shield: "shield.slash.fill"
        case .grace: "shield.fill"
        case .rest: "cup.and.saucer.fill"
        case .completed: "checkmark.seal.fill"
        case .telemetry: "bell.badge.fill"
        }
    }

    var color: Color {
        switch self {
        case .shield: Color(red: 0.85, green: 0.47, blue: 0.02) // Warm amber #d97706
        case .grace: Color(red: 0.31, green: 0.27, blue: 0.90)  // Indigo #4f46e5
        case .rest: Color(red: 0.02, green: 0.59, blue: 0.41)   // Sage #059669
        case .completed: Color(red: 0.02, green: 0.59, blue: 0.41)
        case .telemetry: Color(red: 0.45, green: 0.52, blue: 0.60) // Neutral slate
        }
    }
}

enum ToastContentParser {
    static func classify(_ rawMessage: String) -> (category: ToastCategory, cleanMessage: String) {
        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("blocked") || trimmed.contains("Closed") || trimmed.hasPrefix("🔒") {
            return (.shield, stripLeadingEmoji(trimmed))
        }
        if trimmed.contains("Grace pass") || trimmed.hasPrefix("🛡️") {
            return (.grace, stripLeadingEmoji(trimmed))
        }
        if trimmed.contains("Break") || trimmed.contains("☕️") {
            return (.rest, stripLeadingEmoji(trimmed))
        }
        if trimmed.contains("Saved:") || trimmed.contains("🎉") {
            return (.completed, stripLeadingEmoji(trimmed))
        }
        return (.telemetry, stripLeadingEmoji(trimmed))
    }

    private static func stripLeadingEmoji(_ text: String) -> String {
        var result = text
        for prefix in ["🔒 ", "🛡️ ", "☕️ ", "🎉 ", "🔒", "🛡️", "☕️", "🎉"] {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        if result.hasSuffix(" ☕️") {
            result = String(result.dropLast(" ☕️".count))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Industrial Telemetry HUD toast pill adhering to DESIGN.md System 2.
struct ToastView: View {
    let message: String

    var body: some View {
        let (category, clean) = ToastContentParser.classify(message)
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: category.iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 4.5, height: 4.5)
                    Text(category.tag)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(category.color)
                        .tracking(0.6)
                }

                Text(clean)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(category.color.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
