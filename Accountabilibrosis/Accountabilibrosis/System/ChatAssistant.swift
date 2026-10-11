import Foundation
import Observation

/// STUB — replaced by the gpt-4.1-mini implementation (OpenAIChatClient + tool calls).
/// The chat screen's brain: keeps the conversation, asks about unsure sites, and allows/closes sites via tools.
@Observable @MainActor final class ChatAssistant: SiteAsking {
    /// Conversation shown in ChatView, oldest first.
    private(set) var messages: [ChatMessage] = []
    /// True while a model request is running (ChatView shows a typing indicator).
    private(set) var isThinking = false
    /// Chrome, for allow/close tool calls. Set by AppModel.
    @ObservationIgnored weak var sites: SiteVerdictReceiving?
    /// Called when the assistant needs the user's attention (unsure site, wake greeting): bring up the chat screen.
    @ObservationIgnored var onNeedsAttention: (() -> Void)?

    /// `apiKey` is read on every request, so a key saved in Settings applies immediately.
    init(apiKey: @escaping () -> String?, transport: HTTPTransport = URLSessionTransport()) {}

    /// Clears the conversation and greets the user for a new lock-in on `subject`.
    func beginSession(subject: String) {}
    /// Forgets the session (pending site questions are dropped).
    func endSession() {}
    /// Sends the user's message (typed or dictated) and appends the bot's reply; may call allow/close tools.
    func send(_ text: String) async {}
    func askAboutSite(_ question: SiteQuestion, subject: String) {}
    /// "Welcome back" message after the Mac wakes during a lock-in.
    func greetAfterWake() {}
}
