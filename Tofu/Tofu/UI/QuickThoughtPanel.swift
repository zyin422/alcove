import AppKit
import SwiftUI

/// Floating, focused spotlight-style quick capture bar for intrusive stray thoughts during lock-in.
/// Allows zero-friction thought parking without bringing up the full locked window over the user's workspace.
@MainActor final class QuickThoughtPanelController {
    static let shared = QuickThoughtPanelController()

    private var panel: NSPanel?

    func present(engine: SessionEngine, onParked: ((String) -> Void)? = nil) {
        panel?.close()

        let size = CGSize(width: 480, height: 52)
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - (size.width / 2)
        let y = visible.maxY - 140

        let window = NSPanel(
            contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let view = QuickThoughtView(
            onCommit: { [weak self, weak window] thought in
                let cleaned = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    engine.addParkedThought(cleaned)
                    onParked?(cleaned)
                }
                window?.close()
                self?.panel = nil
            },
            onCancel: { [weak self, weak window] in
                window?.close()
                self?.panel = nil
            }
        )

        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        window.makeKey()
        self.panel = window
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

/// The visual SwiftUI entry field for Quick Thought Capture.
struct QuickThoughtView: View {
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Theme.amber)
                .font(.system(size: 15))

            TextField("Park stray thought… (Return to park, Esc to cancel)", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isFocused)
                .onSubmit {
                    onCommit(text)
                }
                .onExitCommand {
                    onCancel()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            Button {
                onCommit(text)
            } label: {
                Image(systemName: "arrow.return")
                    .font(.system(size: 11, weight: .bold))
                    .padding(5)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.amber.opacity(0.5), lineWidth: 1.5)
        )
        .onAppear {
            isFocused = true
        }
    }
}
