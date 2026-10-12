import Foundation

/// Something the user wants to get done on a day, optionally tied to the setup (subject) it is worked on in.
struct Priority: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var subjectID: UUID?
    var isDone: Bool

    init(id: UUID = UUID(), title: String, subjectID: UUID? = nil, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.isDone = isDone
    }
}

/// The priorities of one day (`DayKey`), and whether that day was wrapped up (recap posted).
struct DayPlan: Codable, Identifiable, Hashable {
    var day: String
    var priorities: [Priority]
    var wrappedUp: Bool

    var id: String { day }

    init(day: String, priorities: [Priority] = [], wrappedUp: Bool = false) {
        self.day = day
        self.priorities = priorities
        self.wrappedUp = wrappedUp
    }
}

/// "2026-10-10"-style keys for days. A day runs from 4 AM to 4 AM, so wrapping up after midnight
/// still counts for the evening before.
enum DayKey {
    static let dayStartHour = 4

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-TimeInterval(dayStartHour) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func tomorrow(from date: Date, calendar: Calendar = .current) -> String {
        key(for: calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400), calendar: calendar)
    }

    /// The day key after `key` ("2026-10-11" → "2026-10-12"). This is a calendar step, not another 4 AM shift.
    static func next(_ key: String, calendar: Calendar = .current) -> String {
        guard let date = date(for: key, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: date) else { return key }
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Noon on the calendar day named by `key`, for labels.
    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Minutes since midnight, counting the small hours (before `dayStartHour`) as 24:00 and later,
    /// so 00:30 is past a 22:00 end of day.
    static func minutesIntoDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        return (hour < dayStartHour ? hour + 24 : hour) * 60 + (parts.minute ?? 0)
    }
}
