import Foundation

/// Time range shown by the stats bar chart.
enum StatsRange: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    /// Segmented-control title.
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// One chart bar: minutes per subject for one day, week or month.
struct StatsBucket: Identifiable, Equatable {
    let start: Date
    let label: String                       // day: "Oct 10", week: "Oct 4", month: "Oct"
    let minutesBySubject: [String: Double]
    var id: Date { start }
    var totalMinutes: Double { minutesBySubject.values.reduce(0, +) }
}

/// Numbers for the summary cards (spec §10).
struct StatsSummary: Equatable {
    var today: TimeInterval
    var thisWeek: TimeInterval
    var currentStreak: Int
    var longestStreak: Int
    var sessionCount: Int
    var average: TimeInterval
    var longest: TimeInterval
    var blockedAttempts: Int
    var closedTabs: Int
    var bails: Int
}

/// Total time of one subject and its fraction of all tracked time.
struct SubjectShare: Identifiable, Equatable {
    let name: String
    let seconds: TimeInterval
    let fraction: Double
    var id: String { name }
}

/// Pure aggregation of sessions into chart buckets, summary numbers and per-subject shares.
/// Sessions with `end == nil` (still active) are ignored everywhere. A session belongs to the
/// calendar day / week / month of its `start` (no midnight splitting).
struct StatsEngine {
    static let streakThreshold: TimeInterval = 300
    static let otherLabel = "Other"
    let calendar: Calendar
    let now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    /// Ignores sessions with end == nil. Oldest -> newest. day: 14 buckets, week: 12, month: 12.
    /// Subjects outside the top `topSubjects` by total time (in the given sessions) are merged into otherLabel.
    func buckets(_ sessions: [Session], range: StatsRange, topSubjects: Int = 5) -> [StatsBucket] {
        let ended = Self.ended(sessions)
        let kept = topNames(ended, limit: topSubjects)
        let starts = bucketStarts(range)
        var minutes: [Date: [String: Double]] = [:]
        for start in starts { minutes[start] = [:] }
        for session in ended {
            let key = periodStart(range.component, for: session.start)
            guard var perSubject = minutes[key] else { continue }
            let name = kept.contains(session.subjectName) ? session.subjectName : Self.otherLabel
            perSubject[name, default: 0] += session.duration / 60
            minutes[key] = perSubject
        }
        let formatter = labelFormatter(range)
        return starts.map { start in
            StatsBucket(start: start, label: formatter.string(from: start), minutesBySubject: minutes[start] ?? [:])
        }
    }

    /// Summary cards. Streaks count days with >= streakThreshold seconds in total; the current streak
    /// ends today, or yesterday when today has not reached the threshold yet.
    func summary(_ sessions: [Session]) -> StatsSummary {
        let ended = Self.ended(sessions)
        let todayStart = periodStart(.day, for: now)
        let weekStart = periodStart(.weekOfYear, for: now)
        var today: TimeInterval = 0
        var thisWeek: TimeInterval = 0
        var perDay: [Date: TimeInterval] = [:]
        for session in ended {
            let day = periodStart(.day, for: session.start)
            perDay[day, default: 0] += session.duration
            if day == todayStart { today += session.duration }
            if periodStart(.weekOfYear, for: session.start) == weekStart { thisWeek += session.duration }
        }
        let qualifying = Set(perDay.filter { $0.value >= Self.streakThreshold }.keys)

        var cursor = qualifying.contains(todayStart) ? todayStart : shiftDay(todayStart, by: -1)
        var currentStreak = 0
        while qualifying.contains(cursor) && currentStreak < qualifying.count {
            currentStreak += 1
            cursor = shiftDay(cursor, by: -1)
        }

        var longestStreak = 0
        var run = 0
        var previous: Date?
        for day in qualifying.sorted() {
            if let previous, shiftDay(previous, by: 1) == day {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            previous = day
        }

        let durations = ended.map(\.duration)
        let total = durations.reduce(0, +)
        return StatsSummary(
            today: today,
            thisWeek: thisWeek,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            sessionCount: ended.count,
            average: ended.isEmpty ? 0 : total / Double(ended.count),
            longest: durations.max() ?? 0,
            blockedAttempts: ended.reduce(0) { $0 + $1.blockedAttempts },
            closedTabs: ended.reduce(0) { $0 + $1.closedTabs },
            bails: ended.filter { $0.outcome == .bailed }.count
        )
    }

    /// Desc by seconds; fraction of total (0 if total == 0).
    func shares(_ sessions: [Session]) -> [SubjectShare] {
        let totals = totalsByName(Self.ended(sessions))
        let total = totals.values.reduce(0, +)
        return Self.ranked(totals).map { entry in
            SubjectShare(name: entry.key, seconds: entry.value, fraction: total > 0 ? entry.value / total : 0)
        }
    }

    // MARK: - Helpers

    private static func ended(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.end != nil }
    }

    /// Seconds per subject name.
    private func totalsByName(_ sessions: [Session]) -> [String: TimeInterval] {
        var totals: [String: TimeInterval] = [:]
        for session in sessions { totals[session.subjectName, default: 0] += session.duration }
        return totals
    }

    /// Desc by value, ties by name asc (stable, deterministic ordering).
    private static func ranked(_ totals: [String: TimeInterval]) -> [(key: String, value: TimeInterval)] {
        totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
    }

    private func topNames(_ sessions: [Session], limit: Int) -> Set<String> {
        Set(Self.ranked(totalsByName(sessions)).prefix(max(0, limit)).map(\.key))
    }

    /// Start of the day / week / month containing `date`.
    private func periodStart(_ component: Calendar.Component, for date: Date) -> Date {
        calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Start of the day `days` days away from the day containing `day`.
    private func shiftDay(_ day: Date, by days: Int) -> Date {
        let shifted = calendar.date(byAdding: .day, value: days, to: day)
            ?? day.addingTimeInterval(TimeInterval(days) * 86_400)
        return periodStart(.day, for: shifted)
    }

    /// Period starts, oldest first, ending with the period containing `now`.
    private func bucketStarts(_ range: StatsRange) -> [Date] {
        let component = range.component
        let current = periodStart(component, for: now)
        return (0..<range.bucketCount).reversed().map { offset in
            let shifted = calendar.date(byAdding: component, value: -offset, to: current) ?? current
            return periodStart(component, for: shifted)
        }
    }

    private func labelFormatter(_ range: StatsRange) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = range == .month ? "MMM" : "MMM d"
        return formatter
    }
}

private extension StatsRange {
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    var bucketCount: Int { self == .day ? 14 : 12 }
}
