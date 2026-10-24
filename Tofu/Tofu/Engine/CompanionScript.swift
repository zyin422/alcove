import Foundation

/// How Moss, the study companion (a small forest spirit), talks.
enum CompanionPersonality: String, Codable, CaseIterable, Identifiable {
    /// Warm and encouraging.
    case gentle
    /// Calm, a little old-fashioned, fond of nature sayings.
    case wise
    /// Bouncy and cheeky.
    case playful

    var id: String { rawValue }

    /// Shown in the Settings picker.
    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .wise: "Wise"
        case .playful: "Playful"
        }
    }

    /// Store files from before Moss saved anime personalities (tsundere, yandere, escalation); those, and any
    /// other unknown value, load as `gentle` instead of failing the whole settings decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionPersonality(rawValue: raw) ?? .gentle
    }
}

/// Which face Moss makes with a line.
enum CompanionExpression: String, CaseIterable {
    case calm, worried, happy, sleepy
}

/// Something that happened during a lock-in that the companion reacts to.
enum CompanionEvent: Equatable {
    case sessionStart(subject: String)
    /// Moss remembers something from an earlier session on this subject (screen memory).
    case recall(subject: String, note: String)
    case blockedApp(name: String)
    case closedTab(host: String)
    case halfway
    case completed
    case forfeit
    case idle
}

/// One thing the companion says, with the face it makes while saying it.
struct CompanionLine: Equatable {
    var text: String
    var expression: CompanionExpression
}

/// Pure dialogue tables: event + personality + violation count in, line out. No UI, no timers.
enum CompanionScript {
    /// Violations (blocked apps + closed tabs) after which Moss stops shrugging distractions off and gets firmer.
    static let concernThreshold = 3

    /// The resting face between lines: worried once distractions keep coming, calm otherwise.
    static func restingExpression(violations: Int) -> CompanionExpression {
        violations >= concernThreshold ? .worried : .calm
    }

    /// The line for `event`. `pick` receives the table size and returns an index (out-of-range is clamped);
    /// the default picks at random.
    static func line(for event: CompanionEvent, personality: CompanionPersonality, violations: Int,
                     pick: (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }) -> CompanionLine {
        let (texts, expression) = table(for: event, personality: personality, firm: violations >= concernThreshold)
        let index = min(max(pick(texts.count), 0), texts.count - 1)
        return CompanionLine(text: texts[index], expression: expression)
    }

    // MARK: Tables

    private static func table(for event: CompanionEvent, personality: CompanionPersonality,
                              firm: Bool) -> (texts: [String], expression: CompanionExpression) {
        switch event {
        case .sessionStart(let subject):
            switch personality {
            case .gentle:
                return (["Hello again. Let's tend to \(subject) together — one small step at a time.",
                         "\(subject) today? I'll sit right here and keep you company."], .happy)
            case .wise:
                return (["The forest grows slowly, and so does understanding. Let us begin \(subject).",
                         "\(subject). Breathe in, settle down. Roots first, then branches."], .calm)
            case .playful:
                return (["Ooh, \(subject)! I brought snacks. Imaginary ones. Let's go!",
                         "\(subject) time! I'll be over here, wiggling encouragingly."], .happy)
            }
        case .recall(_, let note):
            switch personality {
            case .gentle:
                return (["Last time, I saw: \(note) Shall we pick up from there?"], .calm)
            case .wise:
                return (["I remember the last path we walked: \(note)"], .calm)
            case .playful:
                return (["I remember! Last time: \(note) Did I get it right?"], .happy)
            }
        case .blockedApp(let name):
            if firm {
                return (["\(name) again… I tucked it away. Your work is waiting right here, patiently.",
                         "That's a few wanderings now. Let's leave \(name) for later, all right?"], .worried)
            }
            switch personality {
            case .gentle:
                return (["I set \(name) aside for now. It'll be there after.",
                         "Shh, \(name) can wait. Back to the good stuff."], .worried)
            case .wise:
                return (["\(name) is a side path. The main road is still here.",
                         "A river that splits too often never reaches the sea. \(name) can wait."], .worried)
            case .playful:
                return (["Nope! \(name) is napping. Don't wake it.",
                         "I hid \(name) under a leaf. You'll never find it. Back to work!"], .worried)
            }
        case .closedTab(let host):
            if firm {
                return (["I closed \(host) too. You're drifting a little — let's find our way back.",
                         "\(host) again? Let's take one deep breath and return to the work."], .worried)
            }
            switch personality {
            case .gentle:
                return (["I closed \(host) for you. It wasn't part of today's path.",
                         "\(host) can wait until later. You're doing well."], .worried)
            case .wise:
                return (["\(host) has nothing to teach us today. I let it go.",
                         "Not every trail is worth following. \(host) is closed."], .worried)
            case .playful:
                return (["\(host)? Poof! Gone. Magic forest powers.",
                         "Caught you peeking at \(host)! I closed it. Hehe."], .worried)
            }
        case .halfway:
            switch personality {
            case .gentle:
                return (["Halfway there. Look how far you've come!",
                         "Half done already. I'm proud of you."], .happy)
            case .wise:
                return (["Halfway up the hill. The view is already better.",
                         "Half the journey is behind you. Keep a steady pace."], .happy)
            case .playful:
                return (["HALFWAY! *happy leaf noises*",
                         "Half done! I'm doing a tiny dance for you."], .happy)
            }
        case .completed:
            switch personality {
            case .gentle:
                return (["You did it. Rest a little — you've earned it.",
                         "All done. That was good, honest work."], .happy)
            case .wise:
                return (["The seed is planted. Tomorrow it will be a little taller.",
                         "Finished. Every tree is made of quiet days like this one."], .happy)
            case .playful:
                return (["DONE! You're a legend. A small, studious legend!",
                         "Finished! Can we celebrate? I'm celebrating."], .happy)
            }
        case .forfeit:
            switch personality {
            case .gentle:
                return (["That's okay. Some days are heavy. We'll try again soon.",
                         "Stopping early is all right. Be kind to yourself."], .worried)
            case .wise:
                return (["Even the wind rests. Come back when you are ready.",
                         "A step back is still a step on the path."], .worried)
            case .playful:
                return (["Aww, already? Okay… I'll keep your seat warm.",
                         "Fine, fine. But I'm telling the trees about this."], .worried)
            }
        case .idle:
            switch personality {
            case .gentle:
                return (["Still here with you.",
                         "Remember to drink some water.",
                         "You're doing fine. Keep going."], .calm)
            case .wise:
                return (["Moss grows best when left undisturbed. So does focus.",
                         "Slow is smooth. Smooth is fast.",
                         "The rain doesn't hurry, yet it fills the river."], .sleepy)
            case .playful:
                return (["*yawns* I'm not sleepy. You're sleepy.",
                         "I counted 47 leaves while you worked. Keep going!",
                         "Psst. You're doing great. That's all."], .sleepy)
            }
        }
    }
}
