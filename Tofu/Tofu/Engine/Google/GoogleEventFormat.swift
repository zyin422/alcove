import Foundation

/// Read-only display helpers for pulled calendar events (spec §4: no editing, time + title only).
enum GoogleEventFormat {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "9:00 AM – 9:50 AM" for timed events, "All day" for date-only ones.
    static func timeLabel(_ event: GoogleEvent) -> String {
        guard let start = event.start.parsed else { return "All day" }
        let startText = time.string(from: start)
        guard let end = event.end.parsed else { return startText }
        return "\(startText) – \(time.string(from: end))"
    }

    /// Timed events by start; all-day events at the start of their own day so they list first.
    static func sortKey(_ event: GoogleEvent, calendar: Calendar = .current) -> Date {
        if let start = event.start.parsed { return start }
        if let day = event.start.date {
            dayStamp.timeZone = calendar.timeZone
            if let date = dayStamp.date(from: day) { return calendar.startOfDay(for: date) }
        }
        return .distantPast
    }
}
