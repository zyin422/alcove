import SwiftUI

/// Pure rules of the message field (unit-tested).
enum ChatInput {
    /// The message as it will be sent: surrounding whitespace removed.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sending needs some text and a bot that is not already busy answering.
    static func canSend(_ text: String, isThinking: Bool) -> Bool {
        !isThinking && !trimmed(text).isEmpty
    }
}

/// The conversation with the study buddy: bubbles, a typing indicator, a message field and a mic button.
/// Dictation streams live into the field; Return or the arrow sends it.
struct ChatView: View {
    let assistant: ChatAssistant
    @State private var voice = VoiceInput()
    @State private var text = ""
    /// What was in the field when dictation started; non-nil while the transcript should be merged into the field.
    @State private var dictationBase: String?
    @FocusState private var isFieldFocused: Bool

    private static let bottomID = "chat.bottom"

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFieldFocused = true }
        .onDisappear { voice.stop() }
        .onChange(of: voice.transcript) { _, transcript in
            guard let base = dictationBase else { return }
            text = VoiceInput.merged(base: base, transcript: transcript)
        }
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Space.s) {
                    ForEach(assistant.messages) { message in
                        MessageRow(message: message)
                    }
                    if assistant.isThinking {
                        TypingIndicator()
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(Theme.Space.m)
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: assistant.messages.last?.id) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: assistant.isThinking) { _, _ in scrollToBottom(proxy, animated: true) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let error = voice.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.s)
            }
            HStack(spacing: Theme.Space.s) {
                TextField("Message…", text: fieldBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFieldFocused)
                    .onSubmit { submit() }
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .background(Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 1))

                Button { toggleMic() } label: {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(voice.isRecording ? "Stop dictation" : "Dictate a message")
                .accessibilityLabel(voice.isRecording ? "Stop dictation" : "Dictate a message")

                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!ChatInput.canSend(text, isThinking: assistant.isThinking))
                .opacity(ChatInput.canSend(text, isThinking: assistant.isThinking) ? 1 : 0.3)
                .help("Send")
                .accessibilityLabel("Send")
            }
        }
        .padding(Theme.Space.m)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1) }
    }

    /// Typing takes over from dictation: the transcript stops merging and an open microphone is closed.
    private var fieldBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                if newValue != text {
                    dictationBase = nil
                    voice.stop()
                }
                text = newValue
            }
        )
    }

    private func toggleMic() {
        if voice.isRecording {
            voice.stop()
        } else {
            dictationBase = text
            Task { await voice.start() }
        }
    }

    private func submit() {
        guard ChatInput.canSend(text, isThinking: assistant.isThinking) else { return }
        let message = ChatInput.trimmed(text)
        dictationBase = nil
        voice.stop()
        text = ""
        Task { await assistant.send(message) }
    }
}

/// One chat line: bot (avatar + filled bubble, left), user (inverted bubble, right) or a centered notice.
private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .assistant:
            HStack(alignment: .top, spacing: Theme.Space.s) {
                BotAvatar(size: 24)
                Text(message.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)))
                Spacer(minLength: 40)
            }
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lockBackground)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary))
            }
        case .notice:
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xs)
        }
    }
}

/// The bot's "typing" dots: three dots taking turns being bright.
private struct TypingIndicator: View {
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            BotAvatar(size: 24)
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let active = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary.opacity(index == active ? 0.7 : 0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 40)
        }
        .accessibilityLabel("Typing")
    }
}
