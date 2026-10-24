import SwiftUI

/// One subject's page: its name, the Agent / Manual setup switch (top-right), the LOCK IN button, and the setup —
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
            memory: { [model] in MemoryDigest.promptBlock(model.memory.notes(for: subjectID)) }))
    }

    /// The subject's own hue, as in the sidebar.
    private var accent: Color {
        SidebarPalette.color(.init(h: SidebarPalette.hue(for: subject.id), s: 55, l: 50))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    TextField("Name", text: $form.name)
                        .textFieldStyle(.plain)
                        .font(Theme.titleFont)
                        // A focused plain field can shrink to body height and clip the large title.
                        .frame(minHeight: 42)
                        .accessibilityLabel("Subject name")
                    SetupModePicker(mode: $setupMode, accent: accent)
                }
                Button {
                    isChoosingMode = true
                } label: {
                    Text("LOCK IN")
                        .tracking(3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                switch setupMode {
                case .agent:
                    AgentSetupView(agent: agent, form: $form, accent: accent,
                                   suggestions: suggestions,
                                   onEditManually: { withAnimation { setupMode = .manual } })
                case .manual:
                    SubjectForm(form: $form, showsName: false)
                }
                if !form.errors.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(form.errors, id: \.self) { message in
                            Text(message).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                MemoryNotesSection(memory: model.memory, subjectID: subject.id)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
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

    /// Lets the agent read and change this page's form, and lock in on the saved subject.
    private func connectAgent() {
        agent.read = { form }
        agent.apply = { change in change(&form) }
        agent.lockIn = { minutes in
            autosave()
            guard form.errors.isEmpty else { return "The setup isn't complete yet." }
            let mode: SessionMode = minutes > 0 ? .goal(minutes: minutes) : .open
            await model.lockIn(subjectID: subject.id, mode: mode)
            return nil
        }
        agent.greet(isNew: false, name: subject.name,
                    lastNote: model.memory.latest(forSubjectNamed: subject.name)?.summary)
    }

    /// Quick replies offered before the conversation starts.
    private var suggestions: [String] {
        ["Lock in for 50 minutes", "Add another website", "Use the Thirds layout", "Let me keep Notion open"]
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
