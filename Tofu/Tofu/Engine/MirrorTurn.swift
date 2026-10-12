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
    /// Shown as soon as End is pressed, and whenever the model doesn't offer its own replies.
    static let choiceReplies = ["I want to stop", "I need help starting", "I need a break"]

    /// The sheet's first screen, before the model answers. Ending does not happen from this turn.
    static var openingChoices: MirrorTurn {
        MirrorTurn(message: "You asked to end this session. Are you stuck, or are you choosing to stop?",
                   interrogationTurn: 1, intent: "", action: .forceMicroStep,
                   replies: choiceReplies, breakMinutes: breakDefault, parsed: true)
    }

    /// Shown when the model can't be reached. No action, so the session stays up.
    static let unavailable = MirrorTurn(
        message: "The Mirror didn't answer. Keep working, or type the give-up phrase.",
        interrogationTurn: 0, intent: "", action: nil, replies: [], breakMinutes: breakDefault, parsed: false)

    /// A real question can be answered. The unreachable-model line cannot; the give-up phrase is the way out.
    static func acceptsReply(_ turn: MirrorTurn) -> Bool {
        turn.parsed || turn.message != unavailable.message
    }

    /// Forces the action and the next buttons for a known reply, so a wrong model action cannot skip or loop the path.
    /// Free text is left as the model sent it.
    static func applying(_ turn: MirrorTurn, userSaid: String, task: String) -> MirrorTurn {
        guard let path = MirrorPathway.classify(userSaid) else { return turn }
        var turn = turn
        switch path {
        case .helpStarting, .differentStep:
            let keep = turn.action != .confirmForfeit && turn.action != .dismissModal
                && turn.action != .startBreakTimer && isAStep(turn.message)
            turn.action = .forceMicroStep
            turn.parsed = true
            turn.replies = MirrorPathway.helpReplies
            if !keep { turn.message = startingStep(task: task) }
        case .acceptedStep, .keepWorking:
            turn.action = .dismissModal
            turn.parsed = true
            turn.replies = []
        case .wantsToStop:
            let keep = turn.action == .forceMicroStep && isAConfirmation(turn.message)
            turn.action = .forceMicroStep
            turn.parsed = true
            turn.replies = MirrorPathway.stopReplies
            if !keep {
                turn.message = "Confirming ends the session and posts the bail. Is that what you're choosing?"
            }
        case .confirmedStop:
            turn.action = .confirmForfeit
            turn.parsed = true
            turn.replies = []
        case .needsBreak:
            let minutes = turn.breakMinutes == 0 ? breakDefault : turn.breakMinutes
            let keep = isAStep(turn.message) && turn.message.lowercased().contains("break")
            turn.action = .startBreakTimer
            turn.breakMinutes = clampedBreak(minutes)
            turn.parsed = true
            turn.replies = []
            if !keep { turn.message = "Five minutes. The session clock keeps running." }
        }
        return turn
    }

    /// A line the user can act on. A repeated opening question, or a question that asks them to invent the step, is not one.
    static func isAStep(_ message: String) -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != unavailable.message else { return false }
        let lower = text.lowercased()
        if lower.contains("are you stuck") || lower.contains("choosing to stop") || lower.contains("asked to end") {
            return false
        }
        if lower.hasPrefix("what ") || lower.contains("what is the") || lower.contains("what's the")
            || lower.contains("what’s the") {
            return false
        }
        return true
    }

    private static func isAConfirmation(_ message: String) -> Bool {
        let lower = message.lowercased()
        return isAStep(message) && (lower.contains("confirm") || lower.contains("posts the bail") || lower.contains("end the session"))
    }

    static func startingStep(task: String) -> String {
        let name = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "the task" : name
        return "Next two minutes: open \(title) and do the first physical step. Nothing else."
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

/// The three ways out of the opening question, plus the buttons those paths offer next.
/// Close paraphrases of a button take the same path. Anything else is left to the model.
enum MirrorPathway: Equatable {
    case helpStarting
    case differentStep
    case acceptedStep
    case wantsToStop
    case confirmedStop
    case keepWorking
    case needsBreak

    static let helpReplies = ["I'll do that", "That's not the step"]
    static let stopReplies = ["Yes, end it", "No, keep working"]

    static func classify(_ text: String) -> MirrorPathway? {
        let words = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let line = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        guard !line.isEmpty else { return nil }
        if line == "that's not the step" || line == "thats not the step" || line == "that is not the step" {
            return .differentStep
        }
        if line == "i'll do that" || line == "ill do that" || line == "i will do that" { return .acceptedStep }
        if line == "yes end it" { return .confirmedStop }
        if line == "no keep working" { return .keepWorking }
        if line.contains("help") && (line.contains("start") || line.contains("stuck")) { return .helpStarting }
        if line == "i'm stuck" || line == "im stuck" || line == "i am stuck" { return .helpStarting }
        if line.contains("want to stop") { return .wantsToStop }
        if line.contains("need a break") || line.contains("want a break") { return .needsBreak }
        return nil
    }

    /// Appended after the user's line so the model follows the path even when it would copy the opening replies.
    var instruction: String {
        switch self {
        case .helpStarting:
            return "Path A. They asked for help getting started. Give one concrete 2-minute physical action for the active priority. Do not ask them what the step is. Do not repeat the opening question. recommended_action FORCE_MICRO_STEP. suggested_quick_replies must be [\"I'll do that\", \"That's not the step\"]. Do not forfeit and do not start a break."
        case .differentStep:
            return "The step you gave was the wrong one. Give a different 2-minute physical action. recommended_action FORCE_MICRO_STEP. suggested_quick_replies must be [\"I'll do that\", \"That's not the step\"]. Do not forfeit and do not start a break."
        case .acceptedStep:
            return "They accepted the step. recommended_action DISMISS_MODAL. One sentence. suggested_quick_replies []."
        case .wantsToStop:
            return "They want to stop. Ask them to confirm. Say that confirming ends the session and posts the bail. Do not forfeit on this turn. recommended_action FORCE_MICRO_STEP. suggested_quick_replies must be [\"Yes, end it\", \"No, keep working\"]."
        case .confirmedStop:
            return "They confirmed the forfeit. recommended_action CONFIRM_FORFEIT. One sentence. suggested_quick_replies []."
        case .keepWorking:
            return "They chose to keep working. recommended_action DISMISS_MODAL. One sentence. suggested_quick_replies []."
        case .needsBreak:
            return "They asked for a break. recommended_action START_BREAK_TIMER. break_minutes 5 unless they named a length, never above 15. suggested_quick_replies []."
        }
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
            goalMinutes > 0
                ? "Time spent: \(elapsedSeconds) seconds of a \(goalMinutes) minute goal."
                : "Time spent: \(elapsedSeconds) seconds of an open-ended session.",
            "What just happened: \(reason)",
        ]
        if isOpening {
            lines.append("This is interrogation_turn 1. The user has not spoken. Open with the Cold Mirror. "
                + "Do not forfeit and do not start a break until they answer.")
        }
        return lines.joined(separator: "\n")
    }
}
