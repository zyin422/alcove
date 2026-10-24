import SwiftUI

/// How a subject's setup is edited: by talking to the setup agent, or with the form.
enum SetupMode: String, CaseIterable, Identifiable {
    case agent, manual
    var id: String { rawValue }
    var title: String { self == .agent ? "Agent Setup" : "Manual Setup" }
    var systemImage: String { self == .agent ? "sparkles" : "slider.horizontal.3" }
    /// Remembered across subjects and launches.
    static let storageKey = "setupMode"
}

/// Arc-style two-segment switch for the top-right of a setup page: the chosen segment is a raised white pill.
struct SetupModePicker: View {
    @Binding var mode: SetupMode
    let accent: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SetupMode.allCases) { option in
                let isSelected = option == mode
                Button {
                    withAnimation(.spring(duration: 0.25)) { mode = option }
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? (option == .agent ? accent : Color.primary) : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup mode")
    }
}

/// Agent Setup: a command-bar-style chat card (Moss as the agent's face, change chips under its replies) beside a
/// live preview of the setup the agent is filling in. Narrow windows stack the two.
struct AgentSetupView: View {
    let agent: SetupAgent
    @Binding var form: SubjectFormState
    let accent: Color
    let suggestions: [String]
    var onEditManually: () -> Void = {}
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                conversation.frame(minWidth: 380)
                SetupPreviewCard(form: form, accent: accent, onEditManually: onEditManually).frame(width: 250)
            }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                conversation
                SetupPreviewCard(form: form, accent: accent, onEditManually: onEditManually)
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(agent.messages) { message in
                            AgentMessageRow(message: message, accent: accent).id(message.id)
                        }
                        if agent.isThinking {
                            ThinkingRow(accent: accent).id("thinking")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 360)
                .onChange(of: agent.messages.count) {
                    withAnimation { proxy.scrollTo(agent.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: agent.isThinking) {
                    if agent.isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            if agent.messages.count <= 1 && !suggestions.isEmpty {
                suggestionChips
            }
            Divider()
            inputRow
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { submit(suggestion) } label: {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(accent.opacity(0.1)))
                            .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.isThinking)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            TextField("Tell me what you're working on…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit { submit(draft) }
                .accessibilityLabel("Message the setup agent")
            Button { submit(draft) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? accent : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private var canSend: Bool {
        !agent.isThinking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !agent.isThinking else { return }
        draft = ""
        Task { await agent.send(message) }
        isInputFocused = true
    }
}

private struct AgentMessageRow: View {
    let message: AgentMessage
    let accent: Color

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
                    .textSelection(.enabled)
            }
        case .agent:
            HStack(alignment: .top, spacing: 10) {
                MossView(expression: message.changes.isEmpty ? .calm : .happy)
                    .frame(width: 30, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(.system(size: 13.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !message.changes.isEmpty {
                        FlowChips(items: message.changes, accent: accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Change chips that wrap onto new lines.
private struct FlowChips: View {
    let items: [String]
    let accent: Color

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(accent.opacity(0.12)))
            }
        }
    }
}

/// Left-to-right layout that wraps to a new row when the next item doesn't fit.
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ThinkingRow: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            MossView(expression: .sleepy).frame(width: 30, height: 32)
            TimelineView(.animation(minimumInterval: 0.3)) { timeline in
                let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.3) % 3
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle().fill(accent.opacity(index == step ? 0.9 : 0.3)).frame(width: 6, height: 6)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("The setup agent is thinking")
    }
}

/// What the setup looks like right now, updated as the agent works.
struct SetupPreviewCard: View {
    let form: SubjectFormState
    let accent: Color
    var onEditManually: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SETUP").font(Theme.captionFont).foregroundStyle(.secondary)
                Spacer()
                Button("Edit manually", action: onEditManually)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
            }
            Text(form.name.isEmpty ? "Untitled" : form.name)
                .font(.system(size: 17, weight: .semibold))
            if !form.details.isEmpty {
                Text(form.details).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: 10) {
                if form.usesCustomLayout {
                    Image(systemName: "rectangle.3.group").font(.system(size: 22)).frame(width: 64)
                } else {
                    PresetThumbnail(preset: form.preset).frame(width: 64)
                }
                Text(form.usesCustomLayout ? "Custom layout" : form.preset.title).font(.system(size: 12, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(form.visibleSlots.enumerated()), id: \.offset) { index, slot in
                    row(index: index, slot: slot)
                }
            }
            Divider()
            fact("Browser", form.browser.title)
            fact("Other apps", form.unusedApps == .hide ? "Hidden" : "Quit")
            fact("Allowed", form.allowedApps.isEmpty ? "None" : form.allowedApps.map(\.name).joined(separator: ", "))
            if !form.errors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(form.errors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: form)
    }

    private func row(index: Int, slot: SetupSlot) -> some View {
        let urls = slot.urls.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let text: String
        switch slot.kind {
        case .website:
            text = urls.isEmpty ? "Empty" : urls.map { DomainMatcher.host(of: $0) ?? $0 }.joined(separator: ", ")
        case .app:
            text = (slot.app?.name ?? "No app") + (slot.folder.map { " · \(($0 as NSString).lastPathComponent)" } ?? "")
        }
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.18)))
            Image(systemName: slot.kind == .website ? "globe" : "app.dashed").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            Text(value).font(.system(size: 12)).lineLimit(2)
        }
    }
}

/// "What Moss remembers": a subject's screen-memory notes, newest first, each removable.
struct MemoryNotesSection: View {
    let memory: MemoryStore
    let subjectID: UUID
    @State private var showsAll = false

    var body: some View {
        let notes = memory.notes(for: subjectID)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("WHAT MOSS REMEMBERS").font(Theme.captionFont).foregroundStyle(.secondary)
                    Spacer()
                    Button("Forget these") { memory.forget(subjectID: subjectID) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                VStack(spacing: 0) {
                    ForEach(showsAll ? notes : Array(notes.prefix(5))) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Text(note.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.summary).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                                if !note.topics.isEmpty {
                                    Text(note.topics.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Button { memory.delete(note.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Forget this note")
                                .accessibilityLabel("Forget this note")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, Theme.Space.m)
                        if note.id != notes.last?.id { Divider() }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                if notes.count > 5 {
                    Button(showsAll ? "Show fewer" : "Show all \(notes.count)") { showsAll.toggle() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
    }
}
