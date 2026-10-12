import Foundation

/// Duration formatting shared by the timers, stats and Discord messages.
enum TimeFormat {
    /// Upper bound for formatting so absurd inputs can never overflow `Int` (about 31 years).
    private static let maxSeconds: TimeInterval = 1_000_000_000

    /// Floor to minutes: 0 -> "0m", 59*60 -> "59m", 3600 -> "1h 0m", 4800 -> "1h 20m". Negative -> "0m".
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = wholeSeconds(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Floor to seconds: < 1h -> "MM:SS" ("00:00", "59:59"); >= 1h -> "H:MM:SS" ("1:00:00"). Negative -> "00:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(secs))"
    }

    /// Floor to seconds, always "HH:MM:SS": 0 -> "00:00:00", 3599 -> "00:59:59", 360000 -> "100:00:00".
    /// Negative -> "00:00:00". Used by the giant timer.
    static func clockFull(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        return "\(twoDigits(total / 3600)):\(twoDigits((total % 3600) / 60)):\(twoDigits(total % 60))"
    }

    /// Whole, non-negative seconds. NaN, infinities and negatives become 0.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, maxSeconds).rounded(.down))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
