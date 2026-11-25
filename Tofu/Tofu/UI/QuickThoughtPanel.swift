import AppKit
import SwiftUI

private final class QuickThoughtPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Floating, focused spotlight-style quick capture bar for intrusive stray thoughts during lock-in.
/// Allows zero-friction thought parking without bringing up the full locked window over the user's workspace.
@MainActor final class QuickThoughtPanelController {
    static let shared = QuickThoughtPanelController()

    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var escapeMonitor: Any?

    var isPresented: Bool {
        panel != nil && panel?.isVisible == true
    }

    func toggle(
        engine: SessionEngine,
        model: AppModel? = nil,
        onParked: ((String) -> Void)? = nil,
        onPromoted: ((String) -> Void)? = nil
    ) {
        if isPresented {
            close()
        } else {
            present(engine: engine, model: model, onParked: onParked, onPromoted: onPromoted)
        }
    }

    func present(
        engine: SessionEngine,
        model: AppModel? = nil,
        onParked: ((String) -> Void)? = nil,
        onPromoted: ((String) -> Void)? = nil
    ) {
        tearDownPanel(restorePreviousApp: false)

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication = frontmost
        }

        let hasSubjects = !(model?.data.subjects.isEmpty ?? true)
        let size = CGSize(width: 530, height: hasSubjects ? 82 : 52)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - (size.width / 2)
        let y = visible.maxY - 140

        let window = QuickThoughtPanel(
            contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let view = QuickThoughtView(
            subjects: model?.data.subjects ?? [],
            onCommit: { [weak self] thought in
                let cleaned = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    engine.addParkedThought(cleaned)
                    onParked?(cleaned)
                }
                self?.close()
            },
            onPromote: { [weak self] thought in
                let cleaned = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    if let model {
                        let todayKey = DayKey.key(for: Date())
                        let priority = ThoughtParkingEngine.promoteThoughtToPriority(
                            thought: cleaned,
                            subjects: model.data.subjects,
                            fallbackSubjectID: engine.subject?.id
                        )
                        model.updatePlan(day: todayKey) { plan in
                            plan.priorities.append(priority)
                        }
                    } else {
                        engine.addParkedThought(cleaned)
                    }
                    onPromoted?(cleaned)
                }
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.panel = window

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in self?.close() }
                return nil
            }
            return event
        }

        // Promote the SwiftUI TextField's underlying NSTextField to firstResponder immediately on the next tick.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.panel === window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if let field = Self.findTextField(in: window.contentView) {
                window.makeFirstResponder(field)
            }
        }
    }

    func close() {
        tearDownPanel(restorePreviousApp: true)
    }

    private func tearDownPanel(restorePreviousApp: Bool) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel?.close()
        panel = nil
        if restorePreviousApp, let prev = previousApplication {
            prev.activate()
        }
        previousApplication = nil
    }

    private static func findTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }
}

/// The visual SwiftUI entry field for Quick Thought Capture.
struct QuickThoughtView: View {
    var subjects: [Subject] = []
    var onCommit: (String) -> Void
    var onPromote: ((String) -> Void)? = nil
    var onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var parsedPreview: (subject: Subject?, minutes: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        let p = ThoughtParkingEngine.promoteThoughtToPriority(thought: trimmed, subjects: subjects)
        let sub = p.subjectID.flatMap { id in subjects.first(where: { $0.id == id }) }
        return (sub, p.estimatedMinutes)
    }

    var body: some View {
        let preview = parsedPreview
        VStack(spacing: 6) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 15))

                TextField("Park stray thought… (⏎ park, ⌘⏎ add to today)", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isFocused)
                    .onSubmit {
                        onCommit(text)
                    }
                    .onExitCommand {
                        onCancel()
                    }

                if preview.subject != nil || preview.minutes != nil {
                    HStack(spacing: 4) {
                        if let sub = preview.subject {
                            Circle()
                                .fill(Theme.subjectColor(sub.colorHex))
                                .frame(width: 6, height: 6)
                            Text(sub.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.subjectColor(sub.colorHex))
                                .lineLimit(1)
                        }
                        if let mins = preview.minutes {
                            Text("\(mins)m")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .fixedSize()
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

                if onPromote != nil {
                    Button {
                        onPromote?(text)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                            Text("Today")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.emerald.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Park and add to Today's Plan (⌘⏎)")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button {
                    onCommit(text)
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .bold))
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Park thought for later review (⏎)")
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !subjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(subjects.prefix(5)) { sub in
                            let tag = "#" + sub.name.lowercased().replacingOccurrences(of: " ", with: "")
                            Button {
                                if !text.localizedCaseInsensitiveContains(tag) {
                                    text = text.isEmpty ? "\(tag) " : "\(text) \(tag) "
                                }
                                isFocused = true
                            } label: {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Theme.subjectColor(sub.colorHex))
                                        .frame(width: 5, height: 5)
                                    Text(tag)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach([25, 45, 60], id: \.self) { mins in
                            Button {
                                text = text.isEmpty ? "\(mins)m " : "\(text) \(mins)m"
                                isFocused = true
                            } label: {
                                Text("+\(mins)m")
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, subjects.isEmpty ? 0 : 8)
        .frame(height: subjects.isEmpty ? 52 : 82)
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
