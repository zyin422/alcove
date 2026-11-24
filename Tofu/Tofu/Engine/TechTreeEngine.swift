import Foundation

/// Progressive mastery tiers based on cumulative focused hours in a subject.
enum MasteryTier: String, CaseIterable, Comparable, Sendable {
    case novice = "Novice"
    case apprentice = "Apprentice"
    case practitioner = "Practitioner"
    case specialist = "Specialist"
    case master = "Master"
    case grandmaster = "Grandmaster"

    var title: String { rawValue }

    /// Minimum hours required to enter this tier.
    var minHours: Double {
        switch self {
        case .novice: return 0
        case .apprentice: return 2
        case .practitioner: return 10
        case .specialist: return 25
        case .master: return 50
        case .grandmaster: return 100
        }
    }

    /// Next tier in the skill progression.
    var next: MasteryTier? {
        switch self {
        case .novice: return .apprentice
        case .apprentice: return .practitioner
        case .practitioner: return .specialist
        case .specialist: return .master
        case .master: return .grandmaster
        case .grandmaster: return nil
        }
    }

    static func tier(for seconds: TimeInterval) -> MasteryTier {
        let hours = max(0, seconds) / 3600.0
        if hours >= 100 { return .grandmaster }
        if hours >= 50 { return .master }
        if hours >= 25 { return .specialist }
        if hours >= 10 { return .practitioner }
        if hours >= 2 { return .apprentice }
        return .novice
    }

    static func < (lhs: MasteryTier, rhs: MasteryTier) -> Bool {
        lhs.minHours < rhs.minHours
    }
}

/// Identifiers for unlockable skill tree badges.
enum MasteryBadgeID: String, CaseIterable, Identifiable, Sendable {
    case firstStep
    case deepFocus
    case centuryMark
    case priorityCrusher
    case marathoner
    case ironWill
    case dailyDevotion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstStep: return "First Step"
        case .deepFocus: return "Deep Focus"
        case .centuryMark: return "Century Mark"
        case .priorityCrusher: return "Priority Crusher"
        case .marathoner: return "Marathoner"
        case .ironWill: return "Iron Will"
        case .dailyDevotion: return "Daily Devotion"
        }
    }

    var description: String {
        switch self {
        case .firstStep: return "Completed your first focused study session."
        case .deepFocus: return "Completed a 90+ minute session with zero tab or app violations."
        case .centuryMark: return "Accumulated over 100 minutes of deep focus."
        case .priorityCrusher: return "Completed 5 or more scheduled priorities in this subject."
        case .marathoner: return "Reached 25+ cumulative hours of mastery."
        case .ironWill: return "Finished 5 completed sessions without a single bail."
        case .dailyDevotion: return "Studied across 3 or more distinct calendar days."
        }
    }

    var systemImage: String {
        switch self {
        case .firstStep: return "sparkles"
        case .deepFocus: return "brain.head.profile"
        case .centuryMark: return "rosette"
        case .priorityCrusher: return "checklist.checked"
        case .marathoner: return "flame.fill"
        case .ironWill: return "shield.lefthalf.filled"
        case .dailyDevotion: return "calendar.badge.clock"
        }
    }
}

/// A skill badge representing an achievement milestone.
struct MasteryBadge: Identifiable, Equatable, Sendable {
    let id: MasteryBadgeID
    var title: String { id.title }
    var description: String { id.description }
    var systemImage: String { id.systemImage }
    let isUnlocked: Bool

    init(id: MasteryBadgeID, isUnlocked: Bool) {
        self.id = id
        self.isUnlocked = isUnlocked
    }
}

/// Full mastery progression metrics for a specific subject.
struct SubjectMastery: Identifiable, Equatable, Sendable {
    let subject: Subject
    let tier: MasteryTier
    let level: Int
    let xp: Int
    let totalSeconds: TimeInterval
    let completedSessionsCount: Int
    let completedPrioritiesCount: Int
    let progressToNextTier: Double
    let secondsToNextTier: TimeInterval?
    let unlockedBadges: [MasteryBadge]
    let lockedBadges: [MasteryBadge]

    var id: UUID { subject.id }
    var totalHours: Double { totalSeconds / 3600.0 }
}

/// Pure engine for calculating subject mastery, XP, skill tiers, and badges.
enum TechTreeEngine {
    static func computeMastery(
        for subject: Subject,
        sessions: [Session],
        priorities: [Priority],
        calendar: Calendar = .current
    ) -> SubjectMastery {
        let matchingSessions = sessions.filter { $0.subjectID == subject.id }
        let totalSeconds = matchingSessions.reduce(0.0) { $0 + $1.duration }
        let tier = MasteryTier.tier(for: totalSeconds)

        // XP Calculation:
        // 10 XP per minute of focus
        let minutes = Int(totalSeconds / 60.0)
        let baseXP = minutes * 10

        // 25 XP bonus for clean sessions (0 blocked attempts and 0 closed tabs)
        let cleanBonus = matchingSessions.filter { $0.outcome == .completed && $0.blockedAttempts == 0 && $0.closedTabs == 0 }.count * 25

        // 50 XP bonus for each completed priority
        let matchingPriorities = priorities.filter { $0.subjectID == subject.id && $0.isDone }
        let priorityBonus = matchingPriorities.count * 50

        let totalXP = baseXP + cleanBonus + priorityBonus
        // Level curve: Level 1 at 0 XP, grows smoothly with sqrt
        let level = max(1, 1 + Int(sqrt(Double(totalXP) / 50.0)))

        // Tier progress calculation
        let progress: Double
        let secondsToNext: TimeInterval?
        if let nextTier = tier.next {
            let tierMinSec = tier.minHours * 3600.0
            let tierMaxSec = nextTier.minHours * 3600.0
            let range = tierMaxSec - tierMinSec
            let currentInTier = max(0, totalSeconds - tierMinSec)
            progress = range > 0 ? min(1.0, currentInTier / range) : 1.0
            secondsToNext = max(0, tierMaxSec - totalSeconds)
        } else {
            progress = 1.0
            secondsToNext = nil
        }

        // Badges calculation
        var unlocked: [MasteryBadge] = []
        var locked: [MasteryBadge] = []

        for badgeID in MasteryBadgeID.allCases {
            let isUnlocked: Bool
            switch badgeID {
            case .firstStep:
                isUnlocked = !matchingSessions.isEmpty
            case .deepFocus:
                isUnlocked = matchingSessions.contains { $0.duration >= 90 * 60 && $0.blockedAttempts == 0 && $0.closedTabs == 0 }
            case .centuryMark:
                isUnlocked = totalSeconds >= 100 * 60
            case .priorityCrusher:
                isUnlocked = matchingPriorities.count >= 5
            case .marathoner:
                isUnlocked = totalSeconds >= 25 * 3600
            case .ironWill:
                let completedCount = matchingSessions.filter { $0.outcome == .completed }.count
                let bailedCount = matchingSessions.filter { $0.outcome == .bailed }.count
                isUnlocked = completedCount >= 5 && bailedCount == 0
            case .dailyDevotion:
                let distinctDays = Set(matchingSessions.map { session -> String in
                    let comps = calendar.dateComponents([.year, .month, .day], from: session.start)
                    return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
                })
                isUnlocked = distinctDays.count >= 3
            }

            let badge = MasteryBadge(id: badgeID, isUnlocked: isUnlocked)
            if isUnlocked {
                unlocked.append(badge)
            } else {
                locked.append(badge)
            }
        }

        return SubjectMastery(
            subject: subject,
            tier: tier,
            level: level,
            xp: totalXP,
            totalSeconds: totalSeconds,
            completedSessionsCount: matchingSessions.filter { $0.outcome == .completed }.count,
            completedPrioritiesCount: matchingPriorities.count,
            progressToNextTier: progress,
            secondsToNextTier: secondsToNext,
            unlockedBadges: unlocked,
            lockedBadges: locked
        )
    }

    static func computeAll(
        subjects: [Subject],
        sessions: [Session],
        plans: [DayPlan],
        calendar: Calendar = .current
    ) -> [SubjectMastery] {
        let allPriorities = plans.flatMap(\.priorities)
        return subjects.map { computeMastery(for: $0, sessions: sessions, priorities: allPriorities, calendar: calendar) }
    }
}
