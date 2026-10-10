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

    init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date,
         end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0,
         outcome: SessionOutcome? = nil, isDemo: Bool = false) {
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
    }

    /// Seconds from start to end (or to the last heartbeat while active). Never negative.
    var duration: TimeInterval { max(0, (end ?? lastHeartbeat).timeIntervalSince(start)) }
}
