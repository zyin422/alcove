import SwiftUI

/// One subject's page: a header with its name, the Agent / Manual setup switch and the Lock in button, then the setup —
/// edited by talking to the setup agent or with the form, in place. Valid changes save as they are made.
/// Screen memory's notes for the subject are listed at the bottom.
struct SubjectDetailView: View {
    let model: AppModel
    let subject: Subject
    @State private var form: SubjectFormState
    /// What this view last wrote to the model. A `subject` that differs arrived from somewhere
    /// else (e.g. a session saving an allowed site) and replaces the draft.
    @State private var lastSaved: Subject
    @State private var isChoosingMode = false
    @State private var agent: SetupAgent
    @AppStorage(SetupMode.storageKey) private var setupMode = SetupMode.agent

    init(model: AppModel, subject: Subject) {
        self.model = model
        self.subject = subject
        _form = State(initialValue: SubjectFormState(subject: subject))
        _lastSaved = State(initialValue: subject)
        let subjectID = subject.id
        _agent = State(initialValue: SetupAgent(
            apiKey: { [model] in model.openAIKey },
            lookupApp: { [model] name in model.installedApp(named: name) },
            memory: { [model] in MemoryDigest.promptBlock(model.memory.notes(for: subjectID)) },
            context: { [model] in model.agentContext() }))
    }

    /// The subject's own hue, as in the sidebar.
    private var accentHSL: SidebarPalette.HSL { .init(h: SidebarPalette.hue(for: subject.id), s: 55, l: 50) }
    private var accent: Color { SidebarPalette.color(accentHSL) }

    var body: some View {
        PageScrollView(fillsHeight: setupMode == .agent) { page in
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header(compact: page.isCompact)
                switch setupMode {
                case .agent:
                    // Takes the height the header and notes leave, so the conversation grows with the window.
                    AgentSetupView(agent: agent, accent: accent, suggestions: suggestions)
                case .manual:
                    SubjectForm(form: $form, showsName: false,
                                isWide: page.contentWidth >= Theme.Page.twoColumnWidth)
                }
                if !form.errors.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(form.errors, id: \.self) { message in
                            Text(message).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                MemoryNotesSection(memory: model.memory, subjectID: subject.id)
            }
        }
        .navigationTitle(subject.name)
        .onChange(of: form) { autosave() }
        .onChange(of: subject) { _, changed in
            guard changed != lastSaved else { return }
            form = SubjectFormState(subject: changed)
            lastSaved = changed
        }
        .sheet(isPresented: $isChoosingMode) {
            LockInSheet(model: model, subject: subject)
        }
        .onAppear(perform: connectAgent)
    }

    /// The name as the title, then the setup switch and the page's one Lock in button. On a narrow card the switch
    /// shows icons only and the button drops its shortcut hint, so the title keeps room.
    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            TextField("Name", text: $form.name)
                .textFieldStyle(.plain)
                .font(Theme.titleFont)
                // A focused plain field can shrink to body height and clip the large title.
                .frame(minHeight: 42)
                .accessibilityLabel("Subject name")
            SetupModePicker(mode: $setupMode, accent: accent, compact: compact)
                .fixedSize()
            LockInButton(fill: accent, label: Theme.readableText(on: accentHSL), showsShortcut: !compact) {
                isChoosingMode = true
            }
            .fixedSize()
        }
    }

    /// Lets the agent read and change this page's form. Sessions start only from the Lock in button.
    private func connectAgent() {
        agent.read = { form }
        agent.apply = { change in change(&form) }
        agent.greet(name: subject.name, lastNote: model.memory.latest(forSubjectNamed: subject.name)?.summary)
    }

    /// Quick replies offered before the conversation starts.
    private var suggestions: [String] {
        ["Add another website", "Use the Thirds layout", "Let me keep Notion open"]
    }

    /// Saves the form whenever it is valid; an invalid draft keeps the last valid state saved.
    private func autosave() {
        guard form.errors.isEmpty else { return }
        let updated = form.subject(id: subject.id, createdAt: subject.createdAt)
        guard updated != lastSaved else { return }
        lastSaved = updated
        model.updateSubject(updated)
    }
}

/// The subject page's primary action: a compact accent-filled button with a play glyph, "Lock in" and the ⌘↩ hint.
/// It opens the length choice (`LockInSheet`); ⌘↩ works from anywhere on the page.
private struct LockInButton: View {
    let fill: Color
    /// Text color with enough contrast on `fill`.
    let label: Color
    var showsShortcut = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                Text("Lock in").font(.system(size: 13, weight: .semibold))
                if showsShortcut {
                    Text("⌘↩")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.72)
                        .padding(.leading, 1)
                }
            }
            .foregroundStyle(label)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
                    .brightness(isHovered ? 0.05 : 0)
                    .shadow(color: fill.opacity(0.35), radius: isHovered ? 6 : 3, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("Lock in (⌘↩)")
        .accessibilityLabel("Lock in")
        .accessibilityHint("Choose a session length and start")
    }
}

/// Dims a custom-drawn button while it is held.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
