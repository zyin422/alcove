import SwiftUI

/// The interrogation that replaces the give-up phrase while an API key is set. The session ends only when the
/// Mirror's action is a confirmed forfeit. A break pauses monitoring. Anything else leaves the session running.
struct MirrorSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var turn: MirrorTurn?
    @State private var history: [MirrorLine] = []
    @State private var draft = ""
    @State private var phraseDraft = ""
    @State private var isSending = false
    @State private var userHasReplied = false
    @FocusState private var focusedField: Field?

    private enum Field { case answer, phrase }

    /// A question from the Mirror, including prose that wasn't valid JSON. The unreachable line is not one.
    private var canAnswer: Bool { turn.map(MirrorTurn.acceptsReply) ?? false }
    /// The phrase is the way out only when the model didn't return an action the app can follow.
    private var showsBailPhrase: Bool { turn?.parsed == false }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("The Mirror").font(Theme.captionFont).foregroundStyle(.secondary)
            if let turn {
                Text(turn.message)
                    .font(.system(size: 16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if turn.parsed, !turn.replies.isEmpty {
                    replyButtons(turn.replies)
                }
                if canAnswer {
                    TextField("Your answer", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .answer)
                        .onSubmit { send(draft) }
                        .disabled(isSending)
                }
                if showsBailPhrase {
                    giveUpPhrase
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            HStack {
                Spacer()
                Button("Keep working") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if showsBailPhrase {
                    Button("Bail") { bailIfPhraseMatches() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!phraseMatches)
                        .opacity(phraseMatches ? 1 : 0.35)
                }
                if canAnswer {
                    Button("Send") { send(draft) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 480)
        .task { await loadOpening() }
    }

    /// The phrase to type, shown in this sheet. A second sheet cannot present on top of this one.
    private var giveUpPhrase: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(canAnswer ? "Or type this phrase to bail" : "Type this phrase to bail")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(phrase)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .padding(Theme.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1))
            TextField("Type the phrase", text: $phraseDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($focusedField, equals: .phrase)
                .onSubmit { bailIfPhraseMatches() }
        }
    }

    private var phrase: String {
        model.engine.giveUpPhrase(template: model.data.settings.giveUpTemplate, name: model.mirrorTaskName)
    }
    private var phraseMatches: Bool {
        model.engine.phraseMatches(phraseDraft, template: model.data.settings.giveUpTemplate, name: model.mirrorTaskName)
    }

    private func bailIfPhraseMatches() {
        guard phraseMatches else { return }
        let engine = model.engine
        dismiss()
        Task { await engine.bail() }
    }

    private func replyButtons(_ replies: [String]) -> some View {
        FlowReplies(replies: replies) { send($0) }
            .disabled(isSending)
    }

    private func loadOpening() async {
        guard turn == nil else { return }
        await request()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        draft = ""
        userHasReplied = true
        history.append(.user(trimmed))
        Task { await request() }
    }

    private func request() async {
        isSending = true
        let context = model.mirrorContext(reason: "The user asked to end the session early.")
        let reply = await model.mirror.respond(context: context, history: history)
        turn = reply
        history.append(.mirror(reply.message))
        isSending = false
        focusedField = MirrorTurn.acceptsReply(reply) ? .answer : .phrase
        switch MirrorTurn.effect(of: reply, userHasReplied: userHasReplied) {
        case .speak:
            break
        case .dismiss:
            dismiss()
        case .takeBreak(let minutes):
            model.engine.beginBreak(minutes: minutes)
            dismiss()
        case .forfeit:
            let engine = model.engine
            dismiss()
            Task { await engine.bail() }
        }
    }
}

/// Wraps the suggested replies onto as many rows as they need.
private struct FlowReplies: View {
    let replies: [String]
    let send: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(replies, id: \.self) { reply in
                Button(reply) { send(reply) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
