import SwiftUI

/// End-of-day wrap-up in three steps: confirm what got done today, say tomorrow's priorities out loud,
/// then review the list and post the recap (done, not done, tomorrow) to the group chat.
struct EndOfDayView: View {
    let model: AppModel

    private enum Step { case recap, speak, review }

    @State private var step = Step.recap
    @State private var today: [Priority] = []
    /// The day's list as the sheet opened, so saving applies only the user's ticks to the fresh plan.
    @State private var original: [Priority] = []
    @State private var spoken = ""
    @State private var tomorrow: [Priority] = []
    @State private var isMakingList = false
    @State private var plannerLines: [PlannerLine] = []
    @State private var plannerOffline = false
    @State private var voiceIn = VoiceInput()
    @State private var voiceOut = VoiceOutput()
    /// Text already in the box when dictation started, so a restarted hypothesis cannot wipe earlier words.
    @State private var dictationBase: String?

    /// The model runs the tomorrow step when a key is available. A failed opening call falls back to dictation.
    private var usesConversation: Bool { model.hasMirror && !plannerOffline }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            header
            switch step {
            case .recap: recap
            case .speak: speak
            case .review: review
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 520, height: 560, alignment: .topLeading)
        .onAppear {
            today = model.todayPlan().priorities
            original = today
        }
        .onDisappear {
            voiceIn.stop()
            voiceOut.stop()
        }
        .onChange(of: voiceIn.transcript) { _, transcript in
            guard let base = dictationBase else {
                if !transcript.isEmpty { spoken = transcript }
                return
            }
            spoken = VoiceInput.merged(base: base, transcript: transcript)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            BotAvatar(size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(stepCaption).font(Theme.captionFont).foregroundStyle(.secondary)
                Text(stepTitle).font(.system(size: 22, weight: .semibold))
            }
            Spacer()
            Button("Later") { model.isWrappingUpDay = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private var stepCaption: String {
        switch step {
        case .recap: "Wrap up · 1 of 3"
        case .speak: "Wrap up · 2 of 3"
        case .review: "Wrap up · 3 of 3"
        }
    }

    /// The sheet is finishing the previous day, so the list being written is for the current day.
    private var wrappingPreviousDay: Bool { model.todayPlan().day != DayKey.key(for: Date()) }
    private var finishedWord: String { wrappingPreviousDay ? "yesterday" : "today" }
    private var nextWord: String { wrappingPreviousDay ? "today" : "tomorrow" }

    private var stepTitle: String {
        switch step {
        case .recap: "What did you get done \(finishedWord)?"
        case .speak: "What are your priorities for \(nextWord)?"
        case .review: wrappingPreviousDay ? "Today's plan" : "Tomorrow's plan"
        }
    }

    // MARK: Step 1: today

    private var recap: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if today.isEmpty {
                Text("You had no priorities planned for \(finishedWord).").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ForEach($today) { $priority in
                            Toggle(isOn: $priority.isDone) {
                                Text(priority.title)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Next") {
                    step = .speak
                    if model.hasMirror {
                        Task { await openPlanner() }
                    } else {
                        voiceOut.speak("Nice work. What are your priorities for \(nextWord)?")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 160)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Step 2: say tomorrow's priorities

    private var speak: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if usesConversation {
                conversation
            } else {
                Text("Press the mic and list them, e.g. “Finish the CS128 lab, then review MATH241 chapter 4.” You can fix the words below.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: toggleRecording) {
                Label(voiceIn.isRecording ? "Done talking" : "Start talking",
                      systemImage: voiceIn.isRecording ? "stop.circle.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            if let error = voiceIn.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                if voiceIn.needsDictation {
                    Button("Open Dictation settings") { NSWorkspace.shared.open(VoiceInput.dictationSettingsURL) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            TextEditor(text: $spoken)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .frame(minHeight: usesConversation ? 72 : 120)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))

            HStack {
                Button("Back") { step = .recap }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                if isMakingList { ProgressView().controlSize(.small) }
                if usesConversation {
                    Button("Send", action: sendToPlanner)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(width: 120)
                        .disabled(isMakingList || voiceIn.isRecording
                                  || spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Make my list", action: makeList)
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(width: 140)
                        .disabled(isMakingList || voiceIn.isRecording || listSource.isEmpty)
                } else {
                    Button("Make my list", action: makeList)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(width: 180)
                        .disabled(isMakingList || voiceIn.isRecording || listSource.isEmpty)
                }
            }
        }
    }

    /// The model's questions and the user's answers so far.
    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if plannerLines.isEmpty && isMakingList {
                    ProgressView().controlSize(.small)
                }
                ForEach(Array(plannerLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .frame(maxWidth: .infinity, alignment: line.role == "user" ? .trailing : .leading)
                        .foregroundStyle(line.role == "user" ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    /// What "Make my list" turns into priorities: the conversation plus anything still in the box.
    private var listSource: String {
        let said = plannerLines.filter { $0.role == "user" }.map(\.text)
        return (said + [spoken]).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleRecording() {
        if voiceIn.isRecording {
            voiceIn.stop()
            dictationBase = spoken
        } else {
            voiceOut.stop()
            dictationBase = spoken
            Task { await voiceIn.start() }
        }
    }

    private var unfinishedToday: [Priority] { today.filter { !$0.isDone } }

    /// Asks the model to open the tomorrow conversation from what is still unfinished.
    private func openPlanner() async {
        guard plannerLines.isEmpty, !isMakingList, !plannerOffline else { return }
        isMakingList = true
        let turn = await model.priorityExtractor.respond(history: [], unfinished: unfinishedToday,
                                                         subjects: model.data.subjects)
        isMakingList = false
        guard !turn.message.isEmpty || turn.ready else {
            plannerOffline = true
            voiceOut.speak("Nice work. What are your priorities for \(nextWord)?")
            return
        }
        apply(turn)
    }

    private func sendToPlanner() {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isMakingList else { return }
        if voiceIn.isRecording { voiceIn.stop() }
        spoken = ""
        plannerLines.append(.user(text))
        isMakingList = true
        let history = plannerLines
        Task {
            let turn = await model.priorityExtractor.respond(history: history, unfinished: unfinishedToday,
                                                             subjects: model.data.subjects)
            isMakingList = false
            if turn.message.isEmpty && !turn.ready {
                tomorrow = await model.priorityExtractor.priorities(from: listSource, subjects: model.data.subjects)
                step = .review
            } else {
                apply(turn)
            }
        }
    }

    private func apply(_ turn: PlannerTurn) {
        if turn.ready {
            tomorrow = turn.priorities
            step = .review
            return
        }
        if !turn.message.isEmpty {
            plannerLines.append(.assistant(turn.message))
            voiceOut.speak(turn.message)
        }
    }

    private func makeList() {
        let source = listSource
        guard !source.isEmpty else { return }
        if voiceIn.isRecording { voiceIn.stop() }
        isMakingList = true
        Task {
            tomorrow = await model.priorityExtractor.priorities(from: source, subjects: model.data.subjects)
            isMakingList = false
            step = .review
        }
    }

    // MARK: Step 3: review and post

    private var review: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach($tomorrow) { $priority in
                        HStack(spacing: Theme.Space.s) {
                            TextField("Priority", text: $priority.title)
                                .textFieldStyle(.roundedBorder)
                            SetupPicker(subjects: model.data.subjects, selection: $priority.subjectID)
                                .frame(width: 150)
                            Button {
                                tomorrow.removeAll { $0.id == priority.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remove this priority")
                            .accessibilityLabel("Remove this priority")
                        }
                    }
                    Button {
                        tomorrow.append(Priority(title: ""))
                    } label: {
                        Label("Add priority", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(model.data.settings.discordEnabled
                 ? "Posts what you finished, what you didn't, and this plan to the group chat."
                 : "Discord posting is off in Settings, so the recap is only saved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Back") { step = .speak }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(model.data.settings.discordEnabled ? "Post & finish" : "Save & finish") {
                    voiceOut.stop()
                    // Sync may have changed the plan while the sheet was open: tick the fresh plan, not the copy.
                    let fresh = DayPlanner.applyingTicks(edited: today, original: original,
                                                         to: model.todayPlan().priorities)
                    model.wrapUpDay(today: fresh, tomorrow: tomorrow)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 180)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
