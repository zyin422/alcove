import Foundation

/// Pure helpers that turn StatsEngine output into what the Stats screens display.
enum StatsFormatting {
    /// Empty state for the Stats screen and the subject stats section.
    static let emptyMessage = "No sessions yet — lock in to start tracking."

    /// Chart caption per range: "Last 14 days", "Last 12 weeks", "Last 12 months".
    static func rangeCaption(_ range: StatsRange) -> String {
        switch range {
        case .day: return "Last 14 days"
        case .week: return "Last 12 weeks"
        case .month: return "Last 12 months"
        }
    }

    /// One line under a subject: "2 sessions · avg 20m · longest 30m".
    static func subjectLine(sessions: Int, average: TimeInterval, longest: TimeInterval) -> String {
        let count = max(0, sessions)
        let noun = count == 1 ? "session" : "sessions"
        return "\(count) \(noun) · avg \(TimeFormat.short(average)) · longest \(TimeFormat.short(longest))"
    }

    /// "0 days", "1 day", "12 days".
    static func streak(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(max(0, days)) days"
    }

    /// `fraction` clamped to 0...1; NaN and infinities become 0.
    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Rounded whole percent: 0.42 -> "42%", 0.426 -> "43%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((clampedFraction(fraction) * 100).rounded()))%"
    }

    /// Chart series order: subjects by total minutes across `buckets` (desc, ties by name),
    /// StatsEngine.otherLabel always last. Series with no minutes are dropped.
    static func chartSubjects(_ buckets: [StatsBucket]) -> [String] {
        var totals: [String: Double] = [:]
        for bucket in buckets {
            for (name, minutes) in bucket.minutesBySubject {
                totals[name, default: 0] += minutes
            }
        }
        let named = totals
            .filter { $0.key != StatsEngine.otherLabel && $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
        let hasOther = (totals[StatsEngine.otherLabel] ?? 0) > 0
        return hasOther ? named + [StatsEngine.otherLabel] : named
    }

    /// How many x-axis labels fit in a narrow window: 7 of 14 days, 6 of 12 weeks, all 12 short month names.
    static func maxAxisLabels(_ range: StatsRange) -> Int {
        switch range {
        case .day: return 7
        case .week: return 6
        case .month: return 12
        }
    }

    /// At most `maxCount` evenly spaced x-axis labels, oldest first, always including the newest (last) one,
    /// so 14 day labels do not collide in a narrow window.
    static func axisLabels(_ labels: [String], maxCount: Int) -> [String] {
        guard maxCount > 0 else { return [] }
        guard labels.count > maxCount else { return labels }
        let step = Int((Double(labels.count) / Double(maxCount)).rounded(.up))
        let last = labels.count - 1
        return labels.indices.filter { (last - $0) % step == 0 }.map { labels[$0] }
    }

    /// How many subjects get their own chart series so that, with "Other", there are at most `shades` series:
    /// every subject when they fit, otherwise `shades - 1` plus "Other". Counts ended sessions only.
    static func topSubjectLimit(for sessions: [Session], shades: Int) -> Int {
        let names = Set(sessions.filter { $0.end != nil }.map(\.subjectName))
        return names.count <= shades ? max(0, shades) : max(0, shades - 1)
    }

    /// True when at least one session has ended (active sessions are not tracked yet).
    static func hasTrackedSessions(_ sessions: [Session]) -> Bool {
        sessions.contains { $0.end != nil }
    }

    /// Total duration of ended sessions.
    static func totalSeconds(_ sessions: [Session]) -> TimeInterval {
        sessions.filter { $0.end != nil }.reduce(0) { $0 + $1.duration }
    }

    /// Subjects in a period, longest first. Each subject's blocks are oldest first. A live block is left out.
    static func subjectBlocks(_ sessions: [Session]) -> [SubjectBlocks] {
        let ended = sessions.filter { $0.end != nil }
        var groups: [String: [Session]] = [:]
        for session in ended { groups[session.subjectName, default: []].append(session) }
        let totals = groups.mapValues { group in group.reduce(0) { $0 + $1.duration } }
        let total = totals.values.reduce(0, +)
        return totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }.map { name, seconds in
            let blocks = (groups[name] ?? []).sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map { TimeBlock(id: $0.id, subjectName: $0.subjectName, start: $0.start, seconds: $0.duration, notes: $0.notes) }
            return SubjectBlocks(name: name, seconds: seconds, fraction: total > 0 ? seconds / total : 0, blocks: blocks)
        }
    }

    /// Finished blocks, newest first. A block that is still running is left out.
    static func timeBlocks(_ sessions: [Session]) -> [TimeBlock] {
        sessions
            .filter { $0.end != nil }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start > rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { TimeBlock(id: $0.id, subjectName: $0.subjectName, start: $0.start, seconds: $0.duration, notes: $0.notes) }
    }
}

/// One subject's hours in the period being viewed, with its blocks oldest first.
struct SubjectBlocks: Identifiable, Equatable {
    let name: String
    let seconds: TimeInterval
    let fraction: Double
    let blocks: [TimeBlock]
    var id: String { name }
    var sessionCount: Int { blocks.count }
    var average: TimeInterval { blocks.isEmpty ? 0 : seconds / Double(blocks.count) }
    var longest: TimeInterval { blocks.map(\.seconds).max() ?? 0 }
}

/// One finished work block, as shown in the stats list.
struct TimeBlock: Identifiable, Equatable {
    let id: UUID
    let subjectName: String
    let start: Date
    let seconds: TimeInterval
    let notes: String?

    init(id: UUID, subjectName: String, start: Date, seconds: TimeInterval, notes: String? = nil) {
        self.id = id
        self.subjectName = subjectName
        self.start = start
        self.seconds = seconds
        self.notes = notes
    }
}
