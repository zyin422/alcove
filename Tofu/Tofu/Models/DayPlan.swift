import Foundation

/// Something the user wants to get done on a day, optionally tied to the setup (subject) it is worked on in.
struct Priority: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var subjectID: UUID?
    var isDone: Bool
    /// The linked Google Tasks task, once synced.
    var googleTaskID: String?
    /// Estimated time in minutes (e.g. 25, 45, 60), optional.
    var estimatedMinutes: Int?
    /// Scheduled start time in minutes from midnight (e.g. 9 * 60 = 540 for 9:00 AM), optional.
    var scheduledMinutesFromMidnight: Int?
    /// Whether this priority is designated as the primary focus anchor (⭐ Starred) for its subject.
    var isAnchor: Bool

    init(id: UUID = UUID(), title: String, subjectID: UUID? = nil, isDone: Bool = false,
         googleTaskID: String? = nil, estimatedMinutes: Int? = nil,
         scheduledMinutesFromMidnight: Int? = nil, isAnchor: Bool = false) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.isDone = isDone
        self.googleTaskID = googleTaskID
        self.estimatedMinutes = estimatedMinutes
        self.scheduledMinutesFromMidnight = scheduledMinutesFromMidnight
        self.isAnchor = isAnchor
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subjectID, isDone, googleTaskID, estimatedMinutes, scheduledMinutesFromMidnight, isAnchor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subjectID = try container.decodeIfPresent(UUID.self, forKey: .subjectID)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        googleTaskID = try container.decodeIfPresent(String.self, forKey: .googleTaskID)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        scheduledMinutesFromMidnight = try container.decodeIfPresent(Int.self, forKey: .scheduledMinutesFromMidnight)
        isAnchor = try container.decodeIfPresent(Bool.self, forKey: .isAnchor) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subjectID, forKey: .subjectID)
        try container.encode(isDone, forKey: .isDone)
        try container.encodeIfPresent(googleTaskID, forKey: .googleTaskID)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encodeIfPresent(scheduledMinutesFromMidnight, forKey: .scheduledMinutesFromMidnight)
        if isAnchor {
            try container.encode(isAnchor, forKey: .isAnchor)
        }
    }

    /// Formatted time label (e.g. "9:00 AM", or "9:00 AM – 10:30 AM" if duration is known).
    var scheduledTimeLabel: String? {
        guard let startMinutes = scheduledMinutesFromMidnight else { return nil }
        let startH = (startMinutes / 60) % 24
        let startM = startMinutes % 60
        let startPeriod = startH >= 12 ? "PM" : "AM"
        let displayH = startH == 0 ? 12 : (startH > 12 ? startH - 12 : startH)
        let startStr = startM == 0 ? "\(displayH) \(startPeriod)" : String(format: "%d:%02d %@", displayH, startM, startPeriod)

        guard let est = estimatedMinutes, est > 0 else { return startStr }
        let endMinutes = startMinutes + est
        let endH = (endMinutes / 60) % 24
        let endM = endMinutes % 60
        let endPeriod = endH >= 12 ? "PM" : "AM"
        let displayEndH = endH == 0 ? 12 : (endH > 12 ? endH - 12 : endH)
        let endStr = endM == 0 ? "\(displayEndH) \(endPeriod)" : String(format: "%d:%02d %@", displayEndH, endM, endPeriod)
        return "\(startStr) – \(endStr)"
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

    /// Reorders a priority within this plan.
    mutating func movePriority(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < priorities.count,
              destinationIndex >= 0 && destinationIndex < priorities.count,
              sourceIndex != destinationIndex else { return }
        let item = priorities.remove(at: sourceIndex)
        priorities.insert(item, at: destinationIndex)
    }

    /// First pending (uncompleted) priority for a given subject ID, preferring the focus anchor if set.
    func activePriority(for subjectID: UUID) -> Priority? {
        if let anchor = priorities.first(where: { $0.subjectID == subjectID && !$0.isDone && $0.isAnchor }) {
            return anchor
        }
        return priorities.first(where: { $0.subjectID == subjectID && !$0.isDone })
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

    /// The next 4 AM. A wrapped-up day waits until then before asking again.
    static func nextStart(after date: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = dayStartHour
        parts.minute = 0
        parts.second = 0
        let thisMorning = calendar.date(from: parts) ?? date
        if thisMorning > date { return thisMorning }
        return calendar.date(byAdding: .day, value: 1, to: thisMorning) ?? thisMorning.addingTimeInterval(86_400)
    }
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
