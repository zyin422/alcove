import Foundation

/// How the study companion talks. `escalation` starts tsundere and turns yandere after repeated violations.
enum CompanionPersonality: String, Codable, CaseIterable, Identifiable {
    case tsundere
    case yandere
    case escalation

    var id: String { rawValue }

    /// Shown in the Settings picker.
    var title: String {
        switch self {
        case .tsundere: "Tsundere"
        case .yandere: "Yandere"
        case .escalation: "Tsundere → yandere"
        }
    }
}

/// Which portrait the companion shows with a line. Raw values double as the image file names.
enum CompanionExpression: String {
    case neutral, annoyed, pleased, dark
}

/// Something that happened during a lock-in that the companion reacts to.
enum CompanionEvent: Equatable {
    case sessionStart(subject: String)
    case blockedApp(name: String)
    case closedTab(host: String)
    case priorityCompleted(title: String)
    case halfway
    case completed
    case forfeit
    case idle
}

/// One thing the companion says, with the face she makes while saying it.
struct CompanionLine: Equatable {
    var text: String
    var expression: CompanionExpression
}

/// Pure dialogue tables: event + personality + violation count in, line out. No UI, no timers.
enum CompanionScript {
    /// Violations (blocked apps + closed tabs) at which `escalation` flips tsundere → yandere.
    static let escalationThreshold = 3

    /// The mood actually speaking: pure personalities never change; `escalation` flips at the threshold.
    static func mood(for personality: CompanionPersonality, violations: Int) -> CompanionPersonality {
        switch personality {
        case .tsundere, .yandere:
            personality
        case .escalation:
            violations >= escalationThreshold ? .yandere : .tsundere
        }
    }

    /// The line for `event`. `pick` receives the table size and returns an index (out-of-range is clamped);
    /// the default picks at random.
    static func line(for event: CompanionEvent, personality: CompanionPersonality, violations: Int,
                     pick: (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }) -> CompanionLine {
        let isYandere = mood(for: personality, violations: violations) == .yandere
        let (texts, expression) = table(for: event, yandere: isYandere)
        let index = min(max(pick(texts.count), 0), texts.count - 1)
        return CompanionLine(text: texts[index], expression: expression)
    }

    // MARK: Tables

    private static func table(for event: CompanionEvent, yandere: Bool) -> (texts: [String], expression: CompanionExpression) {
        switch event {
        case .sessionStart(let subject):
            return yandere
                ? (["\(subject) time~ It's just the two of us now. Nothing else matters. ♥",
                    "I cleared everything away for \(subject). Look only at your work… and me. ♥"],
                   .neutral)
                : (["Hmph. \(subject) time. I-it's not like I wanted to study with you or anything… Focus, baka!",
                    "\(subject), huh. F-fine, I'll watch. Don't you dare slack off!"],
                   .neutral)
        case .blockedApp(let name):
            return yandere
                ? (["\(name)? Who said you could look at \(name)~? Eyes on your work. Only your work. ♥",
                    "I made \(name) go away. Nothing gets between us… nothing. ♥"],
                   .dark)
                : (["Hey! \(name)?! Seriously? Get back to work, dummy!",
                    "\(name) is blocked, baka! I-I'm not mad. Just… disappointed. Hmph."],
                   .annoyed)
        case .closedTab(let host):
            return yandere
                ? (["\(host)… so that's where you were sneaking off to~ It's gone now. Forever. ♥",
                    "I closed \(host). You don't need anyone but me… and your studies. ♥"],
                   .dark)
                : (["\(host)? Really? I closed it. Don't make that face.",
                    "I threw \(host) away. Y-you should be thanking me, baka!"],
                   .annoyed)
        case .halfway:
            return yandere
                ? (["Halfway~ You've been so good, staying right here with me. ♥",
                    "Half done already~ See how well things go when it's just us? ♥"],
                   .pleased)
                : (["Halfway already…? I-I guess you're not completely hopeless.",
                    "Half done. D-don't get cocky! It's not like I'm impressed or anything."],
                   .pleased)
        case .priorityCompleted(let title):
            return yandere
                ? (["Finished “\(title)”~ Look at us crushing everything together. ♥",
                    "“\(title)” is checked off~ Stay with me for the next one too. ♥"],
                   .pleased)
                : (["“\(title)” done already? W-well… don't celebrate too hard, keep moving!",
                    "Hmph. You knocked out “\(title)” pretty fast. I-I guess that wasn't bad."],
                   .pleased)
        case .completed:
            return yandere
                ? (["You finished~ I knew you would. You'll come back tomorrow… right? Right? ♥",
                    "All done~ You were perfect. We're going to do this forever, you know. ♥"],
                   .pleased)
                : (["Y-you actually did it… I mean — of course you did. I was watching. Good job… baka.",
                    "Done! Hmph. I never doubted you. N-not even once. Don't look at me like that!"],
                   .pleased)
        case .forfeit:
            return yandere
                ? (["…Giving up? After everything I've done for you? …Fine. I'll remember this. ♥",
                    "You're leaving me… I mean, leaving your work? …I see. I see. ♥"],
                   .dark)
                : (["You're giving up?! Fine! See if I care! …I care. Baka.",
                    "Hmph. Quitter. I-it's not like I believed in you anyway…"],
                   .annoyed)
        case .idle:
            return yandere
                ? (["I'm watching~ Always watching. Keep studying. ♥",
                    "Don't mind me. I just like watching you work~ ♥",
                    "Still here~ I'll always be here. Focus. ♥"],
                   .neutral)
                : (["Stop staring at me and study!",
                    "I-I'm only here to make sure you focus. That's all!",
                    "You're doing fine… I guess. K-keep going."],
                   .neutral)
        }
    }
}
