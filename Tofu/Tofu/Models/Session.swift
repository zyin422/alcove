import Foundation

/// Open-ended (count up) or goal (count down from `minutes`).
enum SessionMode: Codable, Hashable {
    case open
    case goal(minutes: Int)

    var goalMinutes: Int? {
        if case .goal(let minutes) = self { return minutes }
        return nil
    }
    var goalSeconds: TimeInterval? { goalMinutes.map { TimeInterval($0 * 60) } }
}

/// How a session ended. `interrupted` = our app quit or crashed mid-session.
enum SessionOutcome: String, Codable {
    case completed, bailed, interrupted
}

/// One lock-in. `end == nil` while it is active.
struct Session: Codable, Identifiable, Hashable {
    var id: UUID
    var subjectID: UUID
    var subjectName: String
    var mode: SessionMode
    var start: Date
    var end: Date?
    var lastHeartbeat: Date
    var blockedAttempts: Int
    var closedTabs: Int
    var outcome: SessionOutcome?
    var isDemo: Bool
    /// Seconds the Mac was asleep during this block. Left out of `duration`. Older saves omit it.
    var excluded: TimeInterval
    /// Stray thoughts jotted down during the session so focus is not broken.
    var parkedThoughts: [String]
    /// History of off-task hosts closed during the block, so the user never fears losing tabs.
    var closedTabHistory: [String]
    /// History of unauthorized apps blocked from launching during the block.
    var blockedAppHistory: [String]
    /// Whether an emergency 2-minute grace pass was used during this lock-in.
    var gracePassUsed: Bool
    /// Optional post-session reflection notes or summary comments.
    var notes: String?

    init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date,
         end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0,
         outcome: SessionOutcome? = nil, isDemo: Bool = false, excluded: TimeInterval = 0,
         parkedThoughts: [String] = [], closedTabHistory: [String] = [], blockedAppHistory: [String] = [],
         gracePassUsed: Bool = false, notes: String? = nil) {
        self.id = id
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.mode = mode
        self.start = start
        self.end = end
        self.lastHeartbeat = lastHeartbeat ?? start
        self.blockedAttempts = blockedAttempts
        self.closedTabs = closedTabs
        self.outcome = outcome
        self.isDemo = isDemo
        self.excluded = excluded
        self.parkedThoughts = parkedThoughts
        self.closedTabHistory = closedTabHistory
        self.blockedAppHistory = blockedAppHistory
        self.gracePassUsed = gracePassUsed
        self.notes = notes
    }

    /// Seconds from start to end (or to the last heartbeat while active), minus time the Mac was asleep.
    var duration: TimeInterval { max(0, (end ?? lastHeartbeat).timeIntervalSince(start) - excluded) }

    enum CodingKeys: String, CodingKey {
        case id, subjectID, subjectName, mode, start, end, lastHeartbeat
        case blockedAttempts, closedTabs, outcome, isDemo, excluded, parkedThoughts, closedTabHistory, blockedAppHistory, gracePassUsed, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        subjectID = try container.decode(UUID.self, forKey: .subjectID)
        subjectName = try container.decode(String.self, forKey: .subjectName)
        mode = try container.decode(SessionMode.self, forKey: .mode)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decodeIfPresent(Date.self, forKey: .end)
        lastHeartbeat = try container.decodeIfPresent(Date.self, forKey: .lastHeartbeat) ?? start
        blockedAttempts = try container.decodeIfPresent(Int.self, forKey: .blockedAttempts) ?? 0
        closedTabs = try container.decodeIfPresent(Int.self, forKey: .closedTabs) ?? 0
        outcome = try container.decodeIfPresent(SessionOutcome.self, forKey: .outcome)
        isDemo = try container.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
        excluded = try container.decodeIfPresent(TimeInterval.self, forKey: .excluded) ?? 0
        parkedThoughts = try container.decodeIfPresent([String].self, forKey: .parkedThoughts) ?? []
        closedTabHistory = try container.decodeIfPresent([String].self, forKey: .closedTabHistory) ?? []
        blockedAppHistory = try container.decodeIfPresent([String].self, forKey: .blockedAppHistory) ?? []
        gracePassUsed = try container.decodeIfPresent(Bool.self, forKey: .gracePassUsed) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}
