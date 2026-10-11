import Foundation

/// What the app does with one Mirror reply, after the user has had a chance to answer.
enum MirrorEffect: Equatable {
    /// Show the line. The session keeps running.
    case speak
    /// Close the sheet. The session keeps running.
    case dismiss
    /// Pause monitoring for this many minutes.
    case takeBreak(minutes: Int)
    /// End the goal as a bail.
    case forfeit
}

/// One Mirror reply. `parsed` is false when the model didn't return the JSON contract; the words are still shown,
/// and the session is not ended.
struct MirrorTurn: Equatable {
    var message: String
    var interrogationTurn: Int
    var intent: String
    var action: MirrorAction?
    var replies: [String]
    var breakMinutes: Int
    var parsed: Bool

    static let breakDefault = 5
    static let breakRange = 1...15

    /// Shown when the model can't be reached. No action, so the session stays up.
    static let unavailable = MirrorTurn(
        message: "The Mirror didn't answer. Keep working, or type the give-up phrase.",
        interrogationTurn: 0, intent: "", action: nil, replies: [], breakMinutes: breakDefault, parsed: false)

    /// A real question can be answered. The unreachable-model line cannot; the give-up phrase is the way out.
    static func acceptsReply(_ turn: MirrorTurn) -> Bool {
        turn.parsed || turn.message != unavailable.message
    }

    /// The opening turn, and any reply that isn't valid JSON, can only be spoken. A forfeit or a break happens
    /// only after the user has replied and the model named that action.
    static func effect(of turn: MirrorTurn, userHasReplied: Bool) -> MirrorEffect {
        guard userHasReplied, turn.parsed, let action = turn.action else { return .speak }
        switch action {
        case .forceMicroStep: return .speak
        case .dismissModal: return .dismiss
        case .startBreakTimer: return .takeBreak(minutes: clampedBreak(turn.breakMinutes))
        case .confirmForfeit: return .forfeit
        }
    }

    static func clampedBreak(_ minutes: Int) -> Int {
        minutes == 0 ? breakDefault : min(max(minutes, breakRange.lowerBound), breakRange.upperBound)
    }

    /// Reads the JSON object. Prose around it, or a ```json fence, is ignored. An unusable reply becomes words only.
    static func parse(_ raw: String) -> MirrorTurn {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonObject(in: trimmed),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            let words = trimmed.isEmpty ? unavailable.message : stripFence(trimmed)
            return MirrorTurn(message: words, interrogationTurn: 0, intent: "", action: nil,
                              replies: [], breakMinutes: breakDefault, parsed: false)
        }
        let message = wire.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let replies = (wire.suggestedQuickReplies ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return MirrorTurn(message: message.isEmpty ? unavailable.message : message,
                          interrogationTurn: wire.interrogationTurn ?? 0,
                          intent: wire.userIntentClassification ?? "",
                          action: wire.recommendedAction.flatMap(MirrorAction.init(rawValue:)),
                          replies: Array(replies.prefix(4)),
                          breakMinutes: clampedBreak(wire.breakMinutes ?? 0),
                          parsed: true)
    }

    private struct Wire: Decodable {
        var message: String
        var interrogationTurn: Int?
        var userIntentClassification: String?
        var recommendedAction: String?
        var suggestedQuickReplies: [String]?
        var breakMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case message
            case interrogationTurn = "interrogation_turn"
            case userIntentClassification = "user_intent_classification"
            case recommendedAction = "recommended_action"
            case suggestedQuickReplies = "suggested_quick_replies"
            case breakMinutes = "break_minutes"
        }
    }

    private static func jsonObject(in text: String) -> Data? {
        let stripped = stripFence(text)
        if let data = stripped.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = stripped.firstIndex(of: "{"), let end = stripped.lastIndex(of: "}"), start < end else { return nil }
        return String(stripped[start...end]).data(using: .utf8)
    }

    private static func stripFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.lowercased().hasPrefix("json") { result = String(result.dropFirst(4)) }
            if let close = result.range(of: "```") { result = String(result[..<close.lowerBound]) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MirrorAction: String, Equatable {
    case forceMicroStep = "FORCE_MICRO_STEP"
    case startBreakTimer = "START_BREAK_TIMER"
    case confirmForfeit = "CONFIRM_FORFEIT"
    case dismissModal = "DISMISS_MODAL"
}

/// Facts the Mirror sees on every turn.
struct MirrorContext: Equatable {
    var priority: String
    var setup: String
    var elapsedSeconds: Int
    var goalMinutes: Int
    /// Why the sheet opened, e.g. "The user asked to end the session early."
    var reason: String

    /// The first user message: the facts, plus the opening instruction when nobody has spoken yet.
    func userMessage(isOpening: Bool) -> String {
        var lines = [
            "Active priority: \(priority)",
            "Setup: \(setup)",
            "Time spent: \(elapsedSeconds) seconds of a \(goalMinutes) minute goal.",
            "What just happened: \(reason)",
        ]
        if isOpening {
            lines.append("This is interrogation_turn 1. The user has not spoken. Open with the Cold Mirror. "
                + "Do not forfeit and do not start a break until they answer.")
        }
        return lines.joined(separator: "\n")
    }
}
