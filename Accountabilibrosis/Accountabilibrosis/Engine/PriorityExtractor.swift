import Foundation

/// One line of the tomorrow conversation.
struct PlannerLine: Equatable {
    var role: String
    var text: String

    static func user(_ text: String) -> PlannerLine { PlannerLine(role: "user", text: text) }
    static func assistant(_ text: String) -> PlannerLine { PlannerLine(role: "assistant", text: text) }
}

/// What the planner says next. `ready` means `priorities` is the list to review.
struct PlannerTurn: Equatable {
    var message: String
    var priorities: [Priority]
    var ready: Bool
}

/// Turns what the user said about tomorrow into a priority list, each matched to a setup when it clearly
/// belongs to one (gpt-4.1-mini). Without a key, or when the reply is unusable, it falls back to
/// `DayPlanner.localPriorities`.
@MainActor final class PriorityExtractor {
    private let apiKey: () -> String?
    private let transport: HTTPTransport

    init(apiKey: @escaping () -> String?, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    func priorities(from spoken: String, subjects: [Subject]) async -> [Priority] {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return [] }
        let key = (apiKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return DayPlanner.localPriorities(from: spoken, subjects: subjects) }
        let client = OpenAIChatClient(apiKey: key, transport: transport)
        let messages: [ChatWireMessage] = [.system(Self.systemPrompt(subjects: subjects)), .user(spoken)]
        guard let reply = try? await client.complete(messages: messages, tools: [], json: true).content,
              let parsed = Self.parse(reply, subjects: subjects), !parsed.isEmpty else {
            return DayPlanner.localPriorities(from: spoken, subjects: subjects)
        }
        return parsed
    }

    /// One turn of the tomorrow conversation. The opening call (empty `history`) asks a question grounded
    /// in what is still unfinished. A later call turns their answer into a list, or asks once more.
    /// Without a key, or when the call fails, `ready` is false and `message` is empty.
    func respond(history: [PlannerLine], unfinished: [Priority], subjects: [Subject]) async -> PlannerTurn {
        let key = (apiKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return PlannerTurn(message: "", priorities: [], ready: false) }
        var messages: [ChatWireMessage] = [.system(Self.conversationPrompt(unfinished: unfinished, subjects: subjects))]
        if history.isEmpty {
            messages.append(.user("The user has not answered yet. Ask one question about tomorrow. ready must be false and priorities must be []."))
        } else {
            messages += history.map { ChatWireMessage(role: $0.role, content: $0.text) }
        }
        let client = OpenAIChatClient(apiKey: key, transport: transport)
        guard let reply = try? await client.complete(messages: messages, tools: [], maxTokens: 500, json: true).content else {
            return PlannerTurn(message: "", priorities: [], ready: false)
        }
        return Self.conversationTurn(from: reply, subjects: subjects)
    }

    nonisolated static func systemPrompt(subjects: [Subject]) -> String {
        let names = subjects.map { "- \($0.name)" }.joined(separator: "\n")
        return """
        The user is saying their priorities for tomorrow out loud (speech-to-text, so expect filler and typos). \
        Turn it into a list of separate priorities, in the order said. Each title is short (at most 8 words), \
        in the user's own words, without numbering or filler like "I need to".
        For each priority pick the setup it is worked on in, only when it clearly belongs to one, else "".
        Setups:
        \(names.isEmpty ? "(none)" : names)
        Reply with JSON only: {"priorities":[{"title":"...","setup":"<setup name or empty>"}]}
        """
    }

    /// The tomorrow conversation. `unfinished` is what they did not tick today.
    nonisolated static func conversationPrompt(unfinished: [Priority], subjects: [Subject]) -> String {
        let left = unfinished.map { item -> String in
            let setup = subjects.first { $0.id == item.subjectID }?.name
            return setup.map { "- \(item.title) (\($0))" } ?? "- \(item.title)"
        }
        let names = subjects.map { "- \($0.name)" }.joined(separator: "\n")
        return """
        You help a student decide tomorrow's priorities. Be brief: one or two sentences, no pep talk.
        Unfinished today:
        \(left.isEmpty ? "(nothing)" : left.joined(separator: "\n"))
        Setups they can lock in on:
        \(names.isEmpty ? "(none)" : names)
        If they have not named tomorrow's tasks, ask one question that uses the unfinished work when there is any. \
        Do not invent a list for them.
        Once they name tasks, stop asking. Set ready to true and return the list, in the order they said. \
        Each title is short (at most 8 words), in their words, without numbering or "I need to". \
        setup is a setup name only when the task clearly belongs to it, else "".
        Carry an unfinished item into tomorrow only when they keep it.
        Reply with JSON only: {"message":"...","ready":false,"priorities":[{"title":"...","setup":""}]}
        """
    }

    /// Reads a conversation reply. Unusable JSON becomes the raw words as a question, not a list.
    nonisolated static func conversationTurn(from reply: String, subjects: [Subject]) -> PlannerTurn {
        let priorities = parse(reply, subjects: subjects) ?? []
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let wire = try? JSONDecoder().decode(ConversationReply.self, from: data) else {
            let words = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return PlannerTurn(message: words, priorities: [], ready: false)
        }
        let message = (wire.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ready = wire.ready == true && !priorities.isEmpty
        return PlannerTurn(message: message, priorities: ready ? priorities : [], ready: ready)
    }

    private struct ConversationReply: Decodable {
        var message: String?
        var ready: Bool?
    }

    private struct Reply: Decodable {
        struct Item: Decodable {
            var title: String
            var setup: String?
        }
        var priorities: [Item]
    }

    /// Reads the JSON reply (code fences and text around it are ignored). Setup names are matched
    /// case-insensitively; unknown names count as no setup. nil when there is no usable JSON.
    nonisolated static func parse(_ reply: String, subjects: [Subject]) -> [Priority]? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let decoded = try? JSONDecoder().decode(Reply.self, from: Data(reply[start...end].utf8)) else { return nil }
        return decoded.priorities.compactMap { item in
            guard let title = DayPlanner.cleanTitle(item.title) else { return nil }
            let setup = (item.setup ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let subject = subjects.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == setup }
            return Priority(title: title, subjectID: subject?.id)
        }
    }
}
