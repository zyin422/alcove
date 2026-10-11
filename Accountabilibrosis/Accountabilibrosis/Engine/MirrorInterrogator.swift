import Foundation

/// One line of the interrogation so far, in order. The opening Mirror line has no user text before it.
struct MirrorLine: Equatable {
    var role: String
    var text: String

    static func user(_ text: String) -> MirrorLine { MirrorLine(role: "user", text: text) }
    static func mirror(_ text: String) -> MirrorLine { MirrorLine(role: "assistant", text: text) }
}

/// Runs one Mirror turn (gpt-4.1-mini) with `MirrorPrompt.system`. Without a key, or when the call fails,
/// returns `MirrorTurn.unavailable`, which never ends the session.
@MainActor final class MirrorInterrogator {
    private let apiKey: () -> String?
    private let transport: HTTPTransport

    init(apiKey: @escaping () -> String?, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    func respond(context: MirrorContext, history: [MirrorLine]) async -> MirrorTurn {
        let key = (apiKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .unavailable }
        var messages: [ChatWireMessage] = [.system(MirrorPrompt.system), .user(context.userMessage(isOpening: history.isEmpty))]
        messages += history.map { ChatWireMessage(role: $0.role, content: $0.text) }
        let client = OpenAIChatClient(apiKey: key, transport: transport)
        guard let reply = try? await client.complete(messages: messages, tools: [], maxTokens: 500, json: true).content else {
            return .unavailable
        }
        let turn = MirrorTurn.parse(reply)
        guard !turn.parsed else { return turn }
        // A prose reply cannot carry an action. Ask once for the JSON object the prompt required.
        messages.append(.assistant(reply))
        messages.append(.user("Reply again with one JSON object only, using the same keys."))
        guard let repaired = try? await client.complete(messages: messages, tools: [], maxTokens: 500, json: true).content else {
            return turn
        }
        let second = MirrorTurn.parse(repaired)
        return second.parsed ? second : turn
    }
}
