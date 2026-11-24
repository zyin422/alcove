import Foundation

/// A single day's focus slice in the 7-day momentum sparkline.
struct DailyFocusSlice: Identifiable, Equatable {
    let dayKey: String
    let dayLabel: String       // e.g. "M", "T", "W"
    let date: Date
    let focusSeconds: TimeInterval
    let isToday: Bool
    let sessionCount: Int

    var id: String { dayKey }
    var focusMinutes: Int { Int(focusSeconds / 60) }
    var focusHoursFormatted: String {
        let hrs = focusSeconds / 3600.0
        return String(format: "%.1fh", hrs)
    }

    init(
        dayKey: String,
        dayLabel: String,
        date: Date,
        focusSeconds: TimeInterval,
        isToday: Bool,
        sessionCount: Int
    ) {
        self.dayKey = dayKey
        self.dayLabel = dayLabel
        self.date = date
        self.focusSeconds = focusSeconds
        self.isToday = isToday
        self.sessionCount = sessionCount
    }
}

/// Summary of 7-day focus momentum: consecutive streak, total week focus, and daily slices.
struct FocusMomentumSummary: Equatable {
    let slices: [DailyFocusSlice]
    let currentStreak: Int
    let totalWeekSeconds: TimeInterval
    let bestDaySeconds: TimeInterval

    var totalWeekHoursFormatted: String {
        let hrs = totalWeekSeconds / 3600.0
        return String(format: "%.1f hrs", hrs)
    }

    init(
        slices: [DailyFocusSlice],
        currentStreak: Int,
        totalWeekSeconds: TimeInterval,
        bestDaySeconds: TimeInterval
    ) {
        self.slices = slices
        self.currentStreak = currentStreak
        self.totalWeekSeconds = totalWeekSeconds
        self.bestDaySeconds = bestDaySeconds
    }
}

/// Computes a factual, non-gamified 7-day focus momentum overview from completed sessions.
enum FocusMomentumEngine {
    private static let minStreakDuration: TimeInterval = 300 // 5 minutes to count as focused day

    static func compute7DayMomentum(
        sessions: [Session],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> FocusMomentumSummary {
        let todayKey = DayKey.key(for: today, calendar: calendar)

        // Filter valid completed non-demo sessions
        let validSessions = sessions.filter { !$0.isDemo && $0.end != nil && $0.duration > 0 }

        // Aggregate duration and count by DayKey
        var dayTotals: [String: TimeInterval] = [:]
        var dayCounts: [String: Int] = [:]

        for s in validSessions {
            let key = DayKey.key(for: s.start, calendar: calendar)
            dayTotals[key, default: 0] += s.duration
            dayCounts[key, default: 0] += 1
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "EEEEE" // Single letter "M", "T", "W", "T", "F", "S", "S"

        var slices: [DailyFocusSlice] = []
        var totalWeekSeconds: TimeInterval = 0
        var bestDaySeconds: TimeInterval = 0

        for offset in (-6...0) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayKey.key(for: date, calendar: calendar)
            let isToday = (key == todayKey)
            let duration = dayTotals[key] ?? 0
            let count = dayCounts[key] ?? 0
            let label = dayFormatter.string(from: date)

            totalWeekSeconds += duration
            if duration > bestDaySeconds {
                bestDaySeconds = duration
            }

            slices.append(DailyFocusSlice(
                dayKey: key,
                dayLabel: label,
                date: date,
                focusSeconds: duration,
                isToday: isToday,
                sessionCount: count
            ))
        }

        // Compute streak continuity
        var streak = 0
        let todayDuration = dayTotals[todayKey] ?? 0
        var checkOffset = todayDuration >= minStreakDuration ? 0 : -1

        while true {
            guard let date = calendar.date(byAdding: .day, value: checkOffset, to: today) else { break }
            let key = DayKey.key(for: date, calendar: calendar)
            let dur = dayTotals[key] ?? 0
            if dur >= minStreakDuration {
                streak += 1
                checkOffset -= 1
            } else {
                break
            }
        }

        return FocusMomentumSummary(
            slices: slices,
            currentStreak: streak,
            totalWeekSeconds: totalWeekSeconds,
            bestDaySeconds: bestDaySeconds
        )
    }
}
