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
}
