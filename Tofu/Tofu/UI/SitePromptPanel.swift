import AppKit
import Observation
import SwiftUI

/// Pure geometry and text for the voice popup (unit-tested).
enum SitePromptLayout {
    static let panelSize = CGSize(width: 360, height: 320)
    static let margin: CGFloat = 16
    /// Bot and user lines shown in the popup (the newest ones).
    static let visibleMessages = 4

    /// Bottom-right corner of `visible`, `margin` in from both edges.
    static func frame(size: CGSize = panelSize, visible: CGRect) -> CGRect {
        CGRect(x: visible.maxX - margin - size.width, y: visible.minY + margin,
               width: size.width, height: size.height)
    }

    /// "Closes in 0:42", never negative.
    static func countdown(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "Closes in %d:%02d", seconds / 60, seconds % 60)
    }
}

/// Runs the voice popup: when the buddy asks about a new site it pops up bottom-right, says the question out loud,
/// and lets the user answer by holding the mic (push to talk). Replies are spoken too. It goes away a moment after
/// the last waiting site is settled. Voice is used only for these site questions.
@Observable @MainActor final class SitePromptController {
    static let hideDelay: TimeInterval = 3
    /// Time for the recognizer to deliver the last words after the mic button is released.
    static let transcriptSettle: TimeInterval = 0.9

    let assistant: ChatAssistant
    let voiceIn = VoiceInput()
    let voiceOut = VoiceOutput.shared
    /// Messages from this id on are shown in the popup (the question that opened it and what followed).
    private(set) var firstMessageID: UUID?
    /// True from releasing the mic until the transcript has been sent.
    private(set) var isSendingSpeech = false
    /// Opens the chat screen ("Open chat").
    @ObservationIgnored var onOpenChat: (() -> Void)?

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(assistant: ChatAssistant) {
        self.assistant = assistant
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The assistant asked about `site`: show the popup (if hidden) and say the question.
    func present(_ site: ChatAssistant.PendingSite) {
        hideTask?.cancel()
        if !isVisible {
            firstMessageID = assistant.messages.last { $0.role == .assistant }?.id
        }
        showPanel()
        if let question = assistant.messages.last(where: { $0.role == .assistant })?.text {
            voiceOut.speak(question)
        }
    }

    /// A new bot line: read it aloud while the popup is up.
    func assistantSaid(_ text: String) {
        guard isVisible else { return }
        voiceOut.speak(text)
    }

    /// Mic button pressed: stop talking and listen.
    func beginTalking() {
        voiceOut.stop()
        hideTask?.cancel()
        Task { await voiceIn.start() }
    }

    /// Mic button released: stop listening and send what was heard.
    func endTalking() {
        voiceIn.stop()
        isSendingSpeech = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.transcriptSettle * 1_000_000_000))
            guard let self else { return }
            let said = self.voiceIn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isSendingSpeech = false
            if !said.isEmpty { await self.assistant.send(said) }
            self.hideIfSettled()
        }
    }

    func allowCurrentSite() {
        guard let host = assistant.pending.first?.host else { return }
        if assistant.allowSiteNow(host) {
            hideIfSettled()
        }
    }

    func closeCurrentSite() {
        guard let host = assistant.pending.first?.host else { return }
        assistant.closeSiteNow(host)
        hideIfSettled()
    }

    func openChat() {
        hide()
        onOpenChat?()
    }

    /// Hides the popup a moment after nothing is waiting anymore, once it has stopped talking and listening.
    func hideIfSettled() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: UInt64(Self.hideDelay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if !self.assistant.pending.isEmpty { return }
                if !self.voiceOut.isSpeaking && !self.voiceIn.isRecording && !self.isSendingSpeech
                    && !self.assistant.isThinking {
                    self.hide()
                    return
                }
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        voiceIn.stop()
        voiceOut.stop()
        panel?.orderOut(nil)
    }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let visible = ScreenGeometry.mainVisibleFrame() {
            panel.setFrame(SitePromptLayout.frame(visible: visible), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: SitePromptLayout.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false   // we are usually not the active app while locked in
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let host = FirstMouseHostingView(rootView: SitePromptView(controller: self))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: SitePromptLayout.panelSize)
        panel.contentView = host
        return panel
    }
}

/// Lets the first click land on a button even though our app is not active (Chrome usually is).
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The popup: the bot's question with a countdown, the latest lines, a live transcript and push-to-talk.
private struct SitePromptView: View {
    let controller: SitePromptController
    @State private var isHolding = false

    private var assistant: ChatAssistant { controller.assistant }

    private var shownMessages: [ChatMessage] {
        let all = assistant.messages
        let start = all.firstIndex { $0.id == controller.firstMessageID } ?? max(0, all.count - 1)
        return Array(all[start...].suffix(SitePromptLayout.visibleMessages))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(shownMessages) { message in
                        line(message)
                    }
                    if controller.voiceIn.isRecording || controller.isSendingSpeech {
                        transcript
                    } else if assistant.isThinking {
                        Text("Thinking…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = controller.voiceIn.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.voiceIn.needsDictation {
                    Button("Open Dictation settings") { NSWorkspace.shared.open(VoiceInput.dictationSettingsURL) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            controls
        }
        .padding(Theme.Space.m)
        .frame(width: SitePromptLayout.panelSize.width, height: SitePromptLayout.panelSize.height)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.lockBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .onChange(of: assistant.pending.isEmpty) { _, isEmpty in
            if isEmpty { controller.hideIfSettled() }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            BotAvatar(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Quick check").font(.system(size: 14, weight: .semibold))
                    if assistant.pending.count > 1 {
                        Text("1 of \(assistant.pending.count)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.amber.opacity(0.16)))
                            .foregroundStyle(Theme.amber)
                    }
                }
                if let waitingHost = assistant.pending.first?.host {
                    Text(waitingHost)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let deadline = assistant.pending.first?.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SitePromptLayout.countdown(until: deadline, now: context.date))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button { controller.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide (the question stays in the chat)")
        }
    }

    @ViewBuilder private func line(_ message: ChatMessage) -> some View {
        switch message.role {
        case .assistant:
            Text(message.text)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lockBackground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary))
            }
        case .notice:
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var transcript: some View {
        HStack {
            Spacer(minLength: 30)
            Text(controller.voiceIn.transcript.isEmpty ? "Listening…" : controller.voiceIn.transcript)
                .font(.system(size: 13).italic())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.s) {
            Label(isHolding ? "Listening… release to send" : "Hold to talk",
                  systemImage: isHolding ? "waveform" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHolding ? Color.lockBackground : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(isHolding ? Color.primary : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else { return }
                        isHolding = true
                        controller.beginTalking()
                    }
                    .onEnded { _ in
                        isHolding = false
                        controller.endTalking()
                    })
                .accessibilityLabel("Hold to talk")
            if let current = assistant.pending.first {
                if ChatAssistant.canQuietlyAllow(current.host) {
                    Button("Keep") { controller.allowCurrentSite() }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Keep this non-distraction site without speaking")
                }
                Button("Close it") { controller.closeCurrentSite() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("Open chat") { controller.openChat() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
