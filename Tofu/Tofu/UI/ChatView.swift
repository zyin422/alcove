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
    @State private var voiceOut = VoiceOutput.shared
    @State private var autoSpeakReplies = false
    @State private var spokeViaVoice = false
    @State private var isDuplexMode = false
    @State private var currentlySpeakingID: UUID?
    @State private var text = ""
    /// What was in the field when dictation started; non-nil while the transcript should be merged into the field.
    @State private var dictationBase: String?
    @FocusState private var isFieldFocused: Bool

    private static let bottomID = "chat.bottom"

    var body: some View {
        VStack(spacing: 0) {
            chatHeaderBar
            messageList
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isFieldFocused = true
            setupVoiceCallbacks()
        }
        .onDisappear {
            isDuplexMode = false
            voice.stop()
            voiceOut.stop()
            currentlySpeakingID = nil
        }
        .onChange(of: voice.transcript) { _, transcript in
            guard let base = dictationBase else { return }
            text = VoiceInput.merged(base: base, transcript: transcript)
        }
        .onChange(of: voiceOut.isSpeaking) { wasSpeaking, isSpeaking in
            if wasSpeaking && !isSpeaking && isDuplexMode && !assistant.isThinking {
                // Assistant finished speaking in duplex mode -> re-open mic for hands-free answer
                rearmDuplexListening()
            }
        }
    }

    // MARK: Header & Messages

    private var chatHeaderBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(assistant.isThinking ? Theme.amber : Theme.emerald)
                    .frame(width: 6, height: 6)
                Text(assistant.subject.isEmpty ? "Study Buddy" : "Study Buddy · \(assistant.subject)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isDuplexMode {
                    Text("Duplex Live")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.indigo.opacity(0.14)))
                        .foregroundStyle(Theme.indigo)
                } else if autoSpeakReplies {
                    Text("Auto-speak")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if assistant.messages.count > 2 && !assistant.isThinking {
                    Button {
                        assistant.clearConversationKeepingSession()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Start fresh conversation thread")
                }
            }
            if let pending = assistant.pending.first {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                    Text("Pending check: \(pending.host)")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if ChatAssistant.canQuietlyAllow(pending.host) {
                        Button("Keep") {
                            _ = assistant.allowSiteNow(pending.host)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Button("Close") {
                        assistant.closeSiteNow(pending.host)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amber.opacity(0.10)))
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Space.s) {
                    ForEach(assistant.messages) { message in
                        MessageRow(
                            message: message,
                            isSpeaking: currentlySpeakingID == message.id && voiceOut.isSpeaking,
                            onSpeak: {
                                if currentlySpeakingID == message.id && voiceOut.isSpeaking {
                                    voiceOut.stop()
                                    currentlySpeakingID = nil
                                } else {
                                    voiceOut.stop()
                                    currentlySpeakingID = message.id
                                    voiceOut.speak(message.text)
                                }
                            }
                        )
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

    private static let quickPrompts: [(label: String, icon: String, prompt: String)] = [
        ("Micro-step", "scope", "Give me one concrete 5-minute micro-step to advance what I'm working on right now."),
        ("Quiz me", "checkmark.bubble", "Ask me one sharp diagnostic question to check my understanding right now."),
        ("Audit tabs", "safari", "Audit my currently open tabs and flag anything that looks off-task."),
        ("Break down", "list.bullet", "Break my current study block into 3 crisp checkpoints."),
    ]

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !assistant.isThinking && !voice.isRecording && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(Self.quickPrompts, id: \.label) { chip in
                            Button {
                                submit(textToSend: chip.prompt)
                            } label: {
                                Label(chip.label, systemImage: chip.icon)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let error = voice.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.s)
                if voice.needsDictation {
                    Button("Open Dictation settings") { NSWorkspace.shared.open(VoiceInput.dictationSettingsURL) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .padding(.horizontal, Theme.Space.s)
                }
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

                Button { toggleDuplex() } label: {
                    Image(systemName: isDuplexMode ? "waveform.badge.mic" : "waveform")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(isDuplexMode ? Theme.indigo : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isDuplexMode ? "Continuous voice duplex active (click to turn off)" : "Enable continuous voice duplex")
                .accessibilityLabel("Voice duplex")

                Button { toggleMic() } label: {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(voice.isRecording ? "Stop dictation" : "Dictate a message")
                .accessibilityLabel(voice.isRecording ? "Stop dictation" : "Dictate a message")

                Button {
                    if voiceOut.isSpeaking {
                        voiceOut.stop()
                        currentlySpeakingID = nil
                    } else {
                        autoSpeakReplies.toggle()
                    }
                } label: {
                    Image(systemName: voiceOut.isSpeaking ? "speaker.wave.3.fill" : (autoSpeakReplies ? "speaker.wave.2.fill" : "speaker.slash"))
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(voiceOut.isSpeaking ? Color.accentColor : (autoSpeakReplies ? Color.primary : Color.secondary))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(voiceOut.isSpeaking ? "Stop talking" : (autoSpeakReplies ? "Voice replies active (click to mute)" : "Enable voice replies"))
                .accessibilityLabel(voiceOut.isSpeaking ? "Stop talking" : (autoSpeakReplies ? "Voice replies active" : "Enable voice replies"))

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
                    if isDuplexMode {
                        isDuplexMode = false
                        voice.autoStopSilenceTimeout = nil
                    }
                    dictationBase = nil
                    voice.stop()
                    voiceOut.stop()
                    currentlySpeakingID = nil
                }
                text = newValue
            }
        )
    }

    private func setupVoiceCallbacks() {
        voice.onSpeechEnded = { finalTranscript in
            guard isDuplexMode else { return }
            submit(textToSend: finalTranscript)
        }
    }

    private func toggleDuplex() {
        voiceOut.stop()
        currentlySpeakingID = nil
        isDuplexMode.toggle()
        if isDuplexMode {
            autoSpeakReplies = true
            voice.autoStopSilenceTimeout = 1.8
            dictationBase = ""
            spokeViaVoice = true
            Task { await voice.start() }
        } else {
            voice.autoStopSilenceTimeout = nil
            voice.stop()
        }
    }

    private func rearmDuplexListening() {
        guard isDuplexMode, !assistant.isThinking, !voice.isRecording else { return }
        dictationBase = ""
        spokeViaVoice = true
        Task { await voice.start() }
    }

    private func toggleMic() {
        voiceOut.stop()
        currentlySpeakingID = nil
        if isDuplexMode {
            isDuplexMode = false
            voice.autoStopSilenceTimeout = nil
        }
        if voice.isRecording {
            voice.stop()
        } else {
            dictationBase = text
            spokeViaVoice = true
            Task { await voice.start() }
        }
    }

    private func submit(textToSend: String? = nil) {
        let candidate = textToSend ?? text
        guard ChatInput.canSend(candidate, isThinking: assistant.isThinking) else { return }
        voiceOut.stop()
        currentlySpeakingID = nil
        let message = ChatInput.trimmed(candidate)
        let wasVoice = spokeViaVoice || dictationBase != nil || isDuplexMode
        dictationBase = nil
        spokeViaVoice = false
        voice.stop()
        text = ""
        Task {
            await assistant.send(message)
            if (wasVoice || autoSpeakReplies),
               let lastReply = assistant.messages.last(where: { $0.role == .assistant }) {
                currentlySpeakingID = lastReply.id
                voiceOut.speak(lastReply.text)
            }
        }
    }
}

/// One chat line: bot (avatar + filled bubble, left), user (inverted bubble, right) or a centered notice.
private struct MessageRow: View {
    let message: ChatMessage
    var isSpeaking: Bool = false
    var onSpeak: (() -> Void)? = nil
    @State private var copied = false

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
                VStack(spacing: 4) {
                    if let onSpeak {
                        Button(action: onSpeak) {
                            Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2")
                                .font(.system(size: 13))
                                .foregroundStyle(isSpeaking ? Color.accentColor : Color.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isSpeaking ? "Stop" : "Read aloud")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copied ? Theme.emerald : Color.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy reply")
                }
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
