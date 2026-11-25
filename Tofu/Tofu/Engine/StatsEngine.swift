import Foundation

/// Which sessions count toward a subject's hours. The sidebar uses `.week`, so each number
/// is only the calendar week that contains today and returns to zero when that week ends.
enum SubjectHoursWindow: String, Codable, CaseIterable, Identifiable {
    case rolling
    case week

    var id: String { rawValue }

    /// Segmented-control title on the stats page.
    var title: String {
        switch self {
        case .rolling: return "Rolling"
        case .week: return "Weekly"
        }
    }

    /// Short label under the subject list.
    var caption: String {
        switch self {
        case .rolling: return "Last 7 days"
        case .week: return "This week"
        }
    }

    /// What the stats page says under the control.
    var detail: String {
        switch self {
        case .rolling:
            return "Each subject’s hours are the last 7 days. A session drops off a week after it started."
        case .week:
            return "Each subject’s hours are this calendar week. They go back to zero when the week changes."
        }
    }

    /// Shown when nothing in this window has ended.
    var emptyHours: String {
        switch self {
        case .rolling: return "No hours in the last 7 days"
        case .week: return "No hours this week"
        }
    }
}

/// One period on the stats page. Day, week, and month show that period alone; year shows its twelve months.
enum StatsSpan: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

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

/// Focus minutes and session count for one hour of the day (0...23).
struct HourlyFocusDensity: Equatable, Identifiable {
    let hour: Int
    let totalMinutes: Double
    let sessionCount: Int
    var id: Int { hour }

    var hourLabel: String {
        let h = hour % 24
        let period = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(displayH) \(period)"
    }
}

/// Dynamic focus velocity score reflecting momentum, volume, and adherence.
struct FocusVelocity: Equatable {
    let score: Int
    let totalMinutes: Double
    let cleanSessionRate: Double
    let completionRate: Double
    let rating: String
}

/// One day cell inside the multi-week consistency heatmap grid.
struct ConsistencyHeatmapDay: Identifiable, Equatable {
    let dayKey: String
    let date: Date
    let totalMinutes: Double
    let sessionCount: Int
    /// Discrete 0...4 intensity tier for monochrome/indigo heatmap rendering.
    let intensityLevel: Int
    var id: String { dayKey }
}

/// Period-over-period delta comparing the current span (`Day` / `Week` / `Month` / `Year`) with its predecessor.
struct PeriodComparison: Equatable {
    let currentTotal: TimeInterval
    let previousTotal: TimeInterval
    let deltaSeconds: TimeInterval
    let deltaPercent: Int?
    let trendLabel: String
}

/// Numbers for the summary cards (spec §10).
struct StatsSummary: Equatable {
    var today: TimeInterval
    var thisWeek: TimeInterval
    /// Sum of the sessions this summary was built from. On the stats page that is the selected range.
    var total: TimeInterval
    var currentStreak: Int
    var longestStreak: Int
    var sessionCount: Int
    var average: TimeInterval
    var longest: TimeInterval
    var blockedAttempts: Int
    var closedTabs: Int
    var bails: Int
    /// Focus purity index (0-100%): ratio of undisturbed focus time after penalizing distraction attempts.
    var focusScore: Int
    /// Total duration spent in deep focus blocks (>= 25 minutes).
    var deepWorkSeconds: TimeInterval

    init(today: TimeInterval = 0, thisWeek: TimeInterval = 0, total: TimeInterval = 0,
         currentStreak: Int = 0, longestStreak: Int = 0, sessionCount: Int = 0,
         average: TimeInterval = 0, longest: TimeInterval = 0, blockedAttempts: Int = 0,
         closedTabs: Int = 0, bails: Int = 0, focusScore: Int = 100,
         deepWorkSeconds: TimeInterval = 0) {
        self.today = today
        self.thisWeek = thisWeek
        self.total = total
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.sessionCount = sessionCount
        self.average = average
        self.longest = longest
        self.blockedAttempts = blockedAttempts
        self.closedTabs = closedTabs
        self.bails = bails
        self.focusScore = focusScore
        self.deepWorkSeconds = deepWorkSeconds
    }
}

/// Total time of one subject, its fraction of the period, and a few counts for that subject.
struct SubjectShare: Identifiable, Equatable {
    let name: String
    let seconds: TimeInterval
    let fraction: Double
    let sessionCount: Int
    let average: TimeInterval
    let longest: TimeInterval
    var id: String { name }
}

/// Pure aggregation of sessions into chart buckets, summary numbers and per-subject shares.
/// Sessions with `end == nil` (still active) are ignored everywhere. A session belongs to the
/// calendar day / week / month of its `start` (no midnight splitting).
struct StatsEngine {
    static let streakThreshold: TimeInterval = 300
    static let otherLabel = "Other"
    /// Length of the rolling subject-hours window.
    static let rollingWindow: TimeInterval = 7 * 24 * 60 * 60
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

    /// Ended sessions whose start falls in the same window the chart draws for `range`.
    func matching(_ sessions: [Session], range: StatsRange) -> [Session] {
        let starts = Set(bucketStarts(range))
        return Self.ended(sessions).filter { starts.contains(periodStart(range.component, for: $0.start)) }
    }

    /// Summary cards for the chart's window: last 14 days, 12 weeks, or 12 months.
    func summary(_ sessions: [Session], range: StatsRange) -> StatsSummary {
        summary(matching(sessions, range: range))
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
        let blocked = ended.reduce(0) { $0 + $1.blockedAttempts }
        let closed = ended.reduce(0) { $0 + $1.closedTabs }
        let score: Int
        if total <= 0 {
            score = 100
        } else {
            let penaltySeconds = Double(blocked + closed) * 180.0
            let ratio = max(0.0, min(1.0, 1.0 - (penaltySeconds / total)))
            score = Int((ratio * 100.0).rounded())
        }
        let deepWork = ended.filter { $0.duration >= 25 * 60 }.reduce(0.0) { $0 + $1.duration }
        return StatsSummary(
            today: today,
            thisWeek: thisWeek,
            total: total,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            sessionCount: ended.count,
            average: ended.isEmpty ? 0 : total / Double(ended.count),
            longest: durations.max() ?? 0,
            blockedAttempts: blocked,
            closedTabs: closed,
            bails: ended.filter { $0.outcome == .bailed }.count,
            focusScore: score,
            deepWorkSeconds: deepWork
        )
    }

    /// Ended sessions whose start falls in `window`. A session stays on the day it started.
    func matching(_ sessions: [Session], window: SubjectHoursWindow) -> [Session] {
        let ended = Self.ended(sessions)
        switch window {
        case .rolling:
            let cutoff = now.addingTimeInterval(-Self.rollingWindow)
            return ended.filter { $0.start >= cutoff }
        case .week:
            let weekStart = periodStart(.weekOfYear, for: now)
            return ended.filter { periodStart(.weekOfYear, for: $0.start) == weekStart }
        }
    }

    /// Hours for one subject inside `window`.
    func seconds(for subjectID: UUID, in sessions: [Session], window: SubjectHoursWindow) -> TimeInterval {
        matching(sessions, window: window)
            .filter { $0.subjectID == subjectID }
            .reduce(0) { $0 + $1.duration }
    }

    /// Start of the day, week, month, or year that contains `date`.
    func startOf(_ span: StatsSpan, containing date: Date) -> Date {
        switch span {
        case .day: return periodStart(.day, for: date)
        case .week: return periodStart(.weekOfYear, for: date)
        case .month: return periodStart(.month, for: date)
        case .year: return periodStart(.year, for: date)
        }
    }

    /// Moves by whole periods. `shift` of a Wednesday by one day is the next midnight, not 24 hours later.
    func shift(_ date: Date, span: StatsSpan, by offset: Int) -> Date {
        let start = startOf(span, containing: date)
        let moved = calendar.date(byAdding: span.step, value: offset, to: start) ?? start
        return startOf(span, containing: moved)
    }

    /// Every period from the earliest ended session through the one containing `now`, including empty ones in between.
    func timeline(_ sessions: [Session], span: StatsSpan) -> [Date] {
        let latest = startOf(span, containing: now)
        let earliest = Self.ended(sessions).map { startOf(span, containing: $0.start) }.min() ?? latest
        var cursor = min(earliest, latest)
        var dates: [Date] = []
        while cursor <= latest && dates.count < 4000 {
            dates.append(cursor)
            let next = shift(cursor, span: span, by: 1)
            if next <= cursor { break }
            cursor = next
        }
        return dates
    }

    /// Ended sessions whose start falls in the period containing `date`.
    func matching(_ sessions: [Session], span: StatsSpan, containing date: Date) -> [Session] {
        let start = startOf(span, containing: date)
        return Self.ended(sessions).filter { startOf(span, containing: $0.start) == start }
    }

    /// Heading for the period containing `date`.
    func heading(_ span: StatsSpan, containing date: Date) -> String {
        let start = startOf(span, containing: date)
        switch span {
        case .day:
            return formatted(start, "EEEE, MMM d")
        case .week:
            let end = shiftDay(start, by: 6)
            return "\(formatted(start, "MMM d")) – \(formatted(end, "MMM d"))"
        case .month:
            return formatted(start, "MMMM yyyy")
        case .year:
            return formatted(start, "yyyy")
        }
    }

    /// Day buttons: "10/10".
    func monthDay(_ date: Date) -> String {
        formatted(startOf(.day, containing: date), "MM/dd")
    }

    /// Short label for a period chip in the scroller.
    func chipTitle(_ span: StatsSpan, containing date: Date) -> String {
        let start = startOf(span, containing: date)
        switch span {
        case .day, .week: return formatted(start, "MMM d")
        case .month: return formatted(start, "MMM")
        case .year: return formatted(start, "yyyy")
        }
    }

    /// Bars for one period. Week is its seven days, month is each day of that month, year is its twelve months.
    /// Day is a single bar; the stats page uses a subject list there instead of this chart.
    func periodBuckets(_ sessions: [Session], span: StatsSpan, containing date: Date, topSubjects: Int = 5) -> [StatsBucket] {
        let anchor = startOf(span, containing: date)
        let starts: [Date]
        let format: String
        let component: Calendar.Component
        switch span {
        case .day:
            starts = [anchor]
            format = "MMM d"
            component = .day
        case .week:
            starts = (0..<7).map { shiftDay(anchor, by: $0) }
            format = "MMM d"
            component = .day
        case .month:
            let days = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
            starts = (0..<days).map { shiftDay(anchor, by: $0) }
            format = "d"
            component = .day
        case .year:
            starts = (0..<12).map { offset in
                let shifted = calendar.date(byAdding: .month, value: offset, to: anchor) ?? anchor
                return periodStart(.month, for: shifted)
            }
            format = "MMM"
            component = .month
        }
        return filledBuckets(sessions, starts: starts, component: component, dateFormat: format, topSubjects: topSubjects)
    }

    /// Per-subject shares inside the chart's window.
    func shares(_ sessions: [Session], range: StatsRange) -> [SubjectShare] {
        shares(matching(sessions, range: range))
    }

    /// Desc by seconds; fraction of total (0 if total == 0). Average and longest are per session of that subject.
    func shares(_ sessions: [Session]) -> [SubjectShare] {
        var durations: [String: [TimeInterval]] = [:]
        for session in Self.ended(sessions) {
            durations[session.subjectName, default: []].append(session.duration)
        }
        let totals = durations.mapValues { $0.reduce(0, +) }
        let total = totals.values.reduce(0, +)
        return Self.ranked(totals).map { entry in
            let times = durations[entry.key] ?? []
            let count = times.count
            return SubjectShare(
                name: entry.key,
                seconds: entry.value,
                fraction: total > 0 ? entry.value / total : 0,
                sessionCount: count,
                average: count == 0 ? 0 : entry.value / Double(count),
                longest: times.max() ?? 0
            )
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
        formatter(range == .month ? "MMM" : "MMM d")
    }

    private func formatted(_ date: Date, _ format: String) -> String {
        formatter(format).string(from: date)
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// Minutes per subject for each `starts` entry. Ranking uses only sessions inside those periods.
    private func filledBuckets(_ sessions: [Session], starts: [Date], component: Calendar.Component,
                               dateFormat: String, topSubjects: Int) -> [StatsBucket] {
        let keys = Set(starts)
        let relevant = Self.ended(sessions).filter { keys.contains(periodStart(component, for: $0.start)) }
        let kept = topNames(relevant, limit: topSubjects)
        var minutes: [Date: [String: Double]] = [:]
        for start in starts { minutes[start] = [:] }
        for session in relevant {
            let key = periodStart(component, for: session.start)
            guard var perSubject = minutes[key] else { continue }
            let name = kept.contains(session.subjectName) ? session.subjectName : Self.otherLabel
            perSubject[name, default: 0] += session.duration / 60
            minutes[key] = perSubject
        }
        let labels = formatter(dateFormat)
        return starts.map { start in
            StatsBucket(start: start, label: labels.string(from: start), minutesBySubject: minutes[start] ?? [:])
        }
    }

    /// Groups session minutes by the starting hour of the day (0 to 23).
    func hourlyDistribution(_ sessions: [Session]) -> [HourlyFocusDensity] {
        var minutesByHour = [Int: Double]()
        var countByHour = [Int: Int]()

        for session in sessions {
            guard session.end != nil else { continue }
            let h = calendar.component(.hour, from: session.start)
            let mins = session.duration / 60.0
            minutesByHour[h, default: 0] += mins
            countByHour[h, default: 0] += 1
        }

        return (0..<24).map { hour in
            HourlyFocusDensity(
                hour: hour,
                totalMinutes: minutesByHour[hour] ?? 0.0,
                sessionCount: countByHour[hour] ?? 0
            )
        }
    }

    /// Evaluates daily/periodic focus velocity based on completed volume, completion integrity, and distraction resistance.
    func focusVelocity(_ sessions: [Session]) -> FocusVelocity {
        guard !sessions.isEmpty else {
            return FocusVelocity(score: 0, totalMinutes: 0, cleanSessionRate: 0, completionRate: 0, rating: "Building")
        }

        let finished = sessions.filter { $0.end != nil }
        guard !finished.isEmpty else {
            return FocusVelocity(score: 0, totalMinutes: 0, cleanSessionRate: 0, completionRate: 0, rating: "Building")
        }

        let totalMins = finished.reduce(0.0) { $0 + ($1.duration / 60.0) }
        let completedSessions = finished.filter { $0.outcome == .completed }.count
        let cleanSessions = finished.filter { $0.outcome == .completed && $0.blockedAttempts == 0 && $0.closedTabs == 0 }.count

        let compRate = Double(completedSessions) / Double(finished.count)
        let cleanRate = Double(cleanSessions) / Double(finished.count)

        // Baseline integrity: up to 40 pts
        let integrityPts = compRate * 40.0
        // Clean focus: up to 30 pts
        let cleanPts = cleanRate * 30.0
        // Volume target (120 min focus = full 30 pts)
        let volumePts = min(30.0, (totalMins / 120.0) * 30.0)

        let rawScore = Int((integrityPts + cleanPts + volumePts).rounded())
        let score = min(100, max(0, rawScore))

        let rating: String
        switch score {
        case 85...100: rating = "Exceptional"
        case 70..<85: rating = "High Momentum"
        case 50..<70: rating = "Steady"
        default: rating = "Building"
        }

        return FocusVelocity(
            score: score,
            totalMinutes: totalMins,
            cleanSessionRate: cleanRate,
            completionRate: compRate,
            rating: rating
        )
    }

    /// Builds `weeks` columns (oldest week left, newest week right), 7 rows per column aligned cleanly to calendar weeks,
    /// showing daily focus intensity (`0...4`) across the recent multi-month window.
    func consistencyHeatmap(sessions: [Session], weeks: Int = 12) -> [[ConsistencyHeatmapDay]] {
        let clampedWeeks = max(1, min(52, weeks))
        let ended = Self.ended(sessions)
        var minutesByDay: [Date: Double] = [:]
        var countByDay: [Date: Int] = [:]

        for session in ended {
            let day = periodStart(.day, for: session.start)
            minutesByDay[day, default: 0] += session.duration / 60.0
            countByDay[day, default: 0] += 1
        }

        let todayDay = periodStart(.day, for: now)
        let currentWeekStart = periodStart(.weekOfYear, for: todayDay)
        guard let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -(clampedWeeks - 1), to: currentWeekStart) else {
            return []
        }

        let keyFormatter = formatter("yyyy-MM-dd")
        var columns: [[ConsistencyHeatmapDay]] = []
        columns.reserveCapacity(clampedWeeks)

        for weekOffset in 0..<clampedWeeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: firstWeekStart) else { continue }
            var col: [ConsistencyHeatmapDay] = []
            col.reserveCapacity(7)
            for dayOffset in 0..<7 {
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dayBucket = periodStart(.day, for: dayDate)
                let key = keyFormatter.string(from: dayBucket)
                let mins = dayBucket > todayDay ? 0 : (minutesByDay[dayBucket] ?? 0)
                let count = dayBucket > todayDay ? 0 : (countByDay[dayBucket] ?? 0)
                let level: Int
                switch mins {
                case ..<1: level = 0
                case 1..<60: level = 1
                case 60..<150: level = 2
                case 150..<270: level = 3
                default: level = 4
                }
                col.append(ConsistencyHeatmapDay(
                    dayKey: key,
                    date: dayBucket,
                    totalMinutes: mins,
                    sessionCount: count,
                    intensityLevel: level
                ))
            }
            columns.append(col)
        }
        return columns
    }

    /// Compares total tracked focus in the selected span against the immediately preceding span.
    func periodComparison(_ sessions: [Session], span: StatsSpan, containing date: Date) -> PeriodComparison {
        let current = matching(sessions, span: span, containing: date)
        let prevDate = shift(date, span: span, by: -1)
        let previous = matching(sessions, span: span, containing: prevDate)

        let currentTotal = Self.ended(current).reduce(0) { $0 + $1.duration }
        let previousTotal = Self.ended(previous).reduce(0) { $0 + $1.duration }
        let delta = currentTotal - previousTotal

        let pct: Int? = previousTotal >= 60
            ? Int(((delta / previousTotal) * 100.0).rounded())
            : nil

        let unit = span.title.lowercased()
        let label: String
        if abs(delta) < 60 {
            label = "Same as prev \(unit)"
        } else {
            let prefix = delta > 0 ? "+" : "-"
            let formatted = TimeFormat.short(abs(delta))
            if let pct {
                let sign = pct > 0 ? "+" : ""
                label = "\(prefix)\(formatted) (\(sign)\(pct)%) vs prev \(unit)"
            } else {
                label = "\(prefix)\(formatted) vs prev \(unit)"
            }
        }

        return PeriodComparison(
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            deltaSeconds: delta,
            deltaPercent: pct,
            trendLabel: label
        )
    }

    /// Aggregates diurnal distribution into four readable dayparts: Morning, Afternoon, Evening, Night.
    func timeOfDayBreakdown(_ sessions: [Session]) -> [(label: String, minutes: Double)] {
        let hours = hourlyDistribution(sessions)
        let morning = hours.filter { (6..<12).contains($0.hour) }.reduce(0.0) { $0 + $1.totalMinutes }
        let afternoon = hours.filter { (12..<18).contains($0.hour) }.reduce(0.0) { $0 + $1.totalMinutes }
        let evening = hours.filter { (18..<24).contains($0.hour) }.reduce(0.0) { $0 + $1.totalMinutes }
        let night = hours.filter { (0..<6).contains($0.hour) }.reduce(0.0) { $0 + $1.totalMinutes }
        return [
            ("Morning", morning),
            ("Afternoon", afternoon),
            ("Evening", evening),
            ("Night", night),
        ]
    }

    /// Last `days` calendar days (oldest to today) of completed non-demo minutes for one subject.
    func subjectRecentActivity(subjectID: UUID, sessions: [Session], days: Int = 7) -> [(label: String, minutes: Double, isToday: Bool)] {
        let count = max(1, days)
        let todayStart = periodStart(.day, for: now)
        let oldest = shiftDay(todayStart, by: -(count - 1))
        var totalsByDay: [Date: TimeInterval] = [:]
        for session in Self.ended(sessions) where session.outcome == .completed && session.subjectID == subjectID {
            let day = periodStart(.day, for: session.start)
            if day >= oldest && day <= todayStart {
                totalsByDay[day, default: 0] += session.duration
            }
        }
        return (0..<count).map { offset in
            let day = shiftDay(oldest, by: offset)
            let weekday = calendar.component(.weekday, from: day)
            let symbol = weekday > 0 && weekday <= calendar.veryShortWeekdaySymbols.count
                ? calendar.veryShortWeekdaySymbols[weekday - 1]
                : ""
            return (symbol, (totalsByDay[day] ?? 0) / 60.0, day == todayStart)
        }
    }
}

/// Highest single-day completed focus total within a period.
struct BestFocusDay: Equatable {
    let date: Date
    let seconds: TimeInterval
    let sessionCount: Int
}

/// Aggregated focus totals for one weekday (Monday through Sunday).
struct WeekdayFocusStat: Identifiable, Equatable {
    let weekday: Int // 2 = Monday ... 7 = Saturday, 1 = Sunday (Calendar weekday numbers)
    let label: String
    let totalMinutes: Double
    let sessionCount: Int
    var id: Int { weekday }
}

extension StatsEngine {
    /// Returns Monday–Sunday focus volume distribution for `sessions` (ended, non-demo).
    func weekdayDistribution(_ sessions: [Session]) -> [WeekdayFocusStat] {
        let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
        let symbols = calendar.shortWeekdaySymbols
        var minsByWeekday: [Int: Double] = [:]
        var countByWeekday: [Int: Int] = [:]
        for session in Self.ended(sessions) {
            let wd = calendar.component(.weekday, from: session.start)
            minsByWeekday[wd, default: 0] += session.duration / 60.0
            countByWeekday[wd, default: 0] += 1
        }
        return mondayFirst.map { wd in
            let label = (wd >= 1 && wd <= symbols.count) ? symbols[wd - 1] : "\(wd)"
            return WeekdayFocusStat(
                weekday: wd,
                label: label,
                totalMinutes: minsByWeekday[wd] ?? 0,
                sessionCount: countByWeekday[wd] ?? 0
            )
        }
    }
    /// Returns the single highest-volume completed focus day across `sessions`, breaking ties toward recent dates.
    func bestFocusDay(in sessions: [Session]) -> BestFocusDay? {
        var byDay: [Date: (seconds: TimeInterval, count: Int)] = [:]
        for session in Self.ended(sessions) where session.outcome == .completed {
            let day = periodStart(.day, for: session.start)
            var current = byDay[day] ?? (0, 0)
            current.seconds += session.duration
            current.count += 1
            byDay[day] = current
        }
        guard let winner = byDay.max(by: { lhs, rhs in
            if abs(lhs.value.seconds - rhs.value.seconds) < 0.5 {
                return lhs.key < rhs.key
            }
            return lhs.value.seconds < rhs.value.seconds
        }), winner.value.seconds > 0 else {
            return nil
        }
        return BestFocusDay(date: winner.key, seconds: winner.value.seconds, sessionCount: winner.value.count)
    }
}

private extension StatsSpan {
    var step: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
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
