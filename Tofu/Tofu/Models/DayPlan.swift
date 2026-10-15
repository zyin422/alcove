import Foundation

/// Something the user wants to get done on a day, optionally tied to the setup (subject) it is worked on in.
struct Priority: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var subjectID: UUID?
    var isDone: Bool
    /// The linked Google Tasks task, once synced.
    var googleTaskID: String?

    init(id: UUID = UUID(), title: String, subjectID: UUID? = nil, isDone: Bool = false,
         googleTaskID: String? = nil) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.isDone = isDone
        self.googleTaskID = googleTaskID
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
        shift(key, by: 1, calendar: calendar)
    }

    /// The day key before `key` ("2026-10-12" → "2026-10-11").
    static func previous(_ key: String, calendar: Calendar = .current) -> String {
        shift(key, by: -1, calendar: calendar)
    }

    private static func shift(_ key: String, by days: Int, calendar: Calendar) -> String {
        guard let date = date(for: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Noon on the calendar day named by `key`, for labels.
    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Year, month, and day of a key. Nil when `key` is not `yyyy-MM-dd`.
    static func parts(of key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, key.count == 10 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    /// Minutes since midnight, counting the small hours (before `dayStartHour`) as 24:00 and later,
    /// so 00:30 is past a 22:00 end of day.
    static func minutesIntoDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        return (hour < dayStartHour ? hour + 24 : hour) * 60 + (parts.minute ?? 0)
    }
}

/// One month laid out as a week grid. Day keys compare in order, so a day is upcoming when its key is after today.
enum DayCalendar {
    struct Cell: Equatable, Identifiable {
        var key: String
        var number: Int
        /// False for the days from the previous or next month that fill out the first and last weeks.
        var inMonth: Bool
        var id: String { key }
    }

    /// True when `key` is after `today`. Equal keys are the current day, not an upcoming one.
    static func isUpcoming(_ key: String, today: String) -> Bool {
        key > today
    }

    static func shiftMonth(year: Int, month: Int, by delta: Int, calendar: Calendar = .current) -> (year: Int, month: Int) {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let shifted = calendar.date(byAdding: .month, value: delta, to: date) else { return (year, month) }
        let parts = calendar.dateComponents([.year, .month], from: shifted)
        return (parts.year ?? year, parts.month ?? month)
    }

    /// Six weeks covering `month`, starting on `calendar.firstWeekday`. Always 42 days, so the calendar
    /// box stays the same size. Neighboring months fill the first and last weeks.
    static func cells(year requestedYear: Int, month requestedMonth: Int, calendar: Calendar = .current) -> [Cell] {
        guard let first = calendar.date(from: DateComponents(year: requestedYear, month: requestedMonth, day: 1)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        let count = 42
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            return Cell(key: String(format: "%04d-%02d-%02d", year, month, day),
                        number: day,
                        inMonth: year == requestedYear && month == requestedMonth)
        }
    }

    /// One letter (or the shortest symbol) for each weekday, beginning on `calendar.firstWeekday`.
    static func weekdayLabels(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % symbols.count] }
    }
}
