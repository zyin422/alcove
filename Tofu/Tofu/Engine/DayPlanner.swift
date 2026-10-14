import Foundation

/// Rules of the daily plan (pure, unit-tested): when to ask to wrap up, which priority a finished lock-in
/// may have completed, and turning spoken words into a priority list without the AI.
enum DayPlanner {
    /// True when the automatic wrap-up should show now: it is on, the end-of-day time has passed, the day was
    /// not wrapped up or prompted yet, and no lock-in is running (it waits until the session ends).
    static func shouldPromptEndOfDay(now: Date, settings: AppSettings, plans: [DayPlan], isLocked: Bool,
                                     calendar: Calendar = .current) -> Bool {
        guard settings.dayEndPromptEnabled, !isLocked else { return false }
        let today = DayKey.key(for: now, calendar: calendar)
        guard settings.lastDayPromptKey != today,
              plans.first(where: { $0.day == today })?.wrappedUp != true else { return false }
        return DayKey.minutesIntoDay(now, calendar: calendar) >= settings.dayEndMinutes
    }

    /// True when the morning screen should show now: it is on, it was not shown yet today (`DayKey`, so a day
    /// starts at 4 AM), nothing is running or on screen, and the end-of-day time has not come yet.
    static func shouldShowMorning(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool,
                                  calendar: Calendar = .current) -> Bool {
        guard settings.morningScreenEnabled, !isLocked, !isBusy,
              settings.lastMorningKey != DayKey.key(for: now, calendar: calendar) else { return false }
        return DayKey.minutesIntoDay(now, calendar: calendar) < settings.dayEndMinutes
    }

    /// The day Today shows. This is the current day (a day runs from 4 AM). Wrapping up saves the next
    /// list on the next calendar day and does not move Today forward. If the previous day has a plan
    /// that was never wrapped up, that day stays on screen until it is wrapped up.
    static func workingDay(now: Date, plans: [DayPlan], calendar: Calendar = .current) -> String {
        let today = DayKey.key(for: now, calendar: calendar)
        let yesterday = DayKey.previous(today, calendar: calendar)
        if plans.first(where: { $0.day == yesterday })?.wrappedUp == false {
            return yesterday
        }
        return today
    }

    /// "Good morning" / "Good afternoon" / "Good evening" for the hour of `now`.
    static func greeting(at now: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: now) {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// The first unfinished priority of `plan` tied to the session's setup, nil when there is none
    /// or the session was interrupted (the app quit).
    static func priorityToConfirm(after session: Session, in plan: DayPlan?) -> Priority? {
        guard let plan, let outcome = session.outcome, outcome != .interrupted else { return nil }
        return plan.priorities.first { !$0.isDone && $0.subjectID == session.subjectID }
    }

    // MARK: Spoken list -> priorities

    /// Splits "finish the CS128 lab, then review calc and also call mom" into separate titles.
    /// Splits on commas, semicolons, new lines, numbering and "(and) then / also / next / after that".
    static func splitSpokenList(_ text: String) -> [String] {
        let separators = #"(?i)\s*(?:[,;\n]|\d+[.)]\s|\b(?:and\s+)?(?:then|also|next|after that)\b)\s*"#
        let parts = text.replacingOccurrences(of: separators, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
        return parts.compactMap(cleanTitle)
    }

    /// Trims filler from the start ("and", "I need to", "tomorrow I want to"…) and the final period;
    /// nil when nothing is left.
    static func cleanTitle(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let filler = #"(?i)^(?:and\s+|so\s+|um+\s+|uh+\s+|first\s+|second\s+|third\s+|finally\s+|lastly\s+|tomorrow\s+|"#
            + #"i\s+(?:need|want|have|would like|'d like|should|will|'ll)\s+to\s+|i(?:'ll| will)\s+|my priorities are\s+)+"#
        title = (title + " ").replacingOccurrences(of: filler, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !title.isEmpty else { return nil }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// The setup whose name appears in `title` (case-insensitive, whole words); the longest name wins.
    static func matchSubject(_ title: String, subjects: [Subject]) -> UUID? {
        let lowered = title.lowercased()
        return subjects
            .filter { subject in
                let name = subject.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !name.isEmpty else { return false }
                let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}])"#
                return lowered.range(of: pattern, options: .regularExpression) != nil
            }
            .max { $0.name.count < $1.name.count }?
            .id
    }

    /// Local fallback for `PriorityExtractor`: split the words and match setups by name.
    static func localPriorities(from text: String, subjects: [Subject]) -> [Priority] {
        splitSpokenList(text).map { Priority(title: $0, subjectID: matchSubject($0, subjects: subjects)) }
    }
}

/// One number for the day the bot posts with the recap, and the counts behind it.
/// Score is 0...100: 50 for priorities finished, 30 for focus time (full at 90 minutes), 20 for not bailing.
/// A day with no sessions and no priorities scores 0.
struct DaySummary: Equatable {
    static let focusForFullMarks: TimeInterval = 90 * 60

    var focusSeconds: TimeInterval
    var sessionCount: Int
    var bails: Int
    var blockedAttempts: Int
    var closedTabs: Int
    var prioritiesDone: Int
    var prioritiesTotal: Int

    var score: Int {
        guard sessionCount > 0 || prioritiesTotal > 0 else { return 0 }
        let priorities = prioritiesTotal == 0
            ? 0
            : Int((50.0 * Double(prioritiesDone) / Double(prioritiesTotal)).rounded())
        let focus = Int((30.0 * min(focusSeconds / Self.focusForFullMarks, 1)).rounded())
        let followThrough = bails == 0 ? 20 : 0
        return min(100, priorities + focus + followThrough)
    }

    /// "📊 Score 74 · 1h 20m focused · 2/3 priorities · 0 bails", plus blocked apps and closed tabs when there were any.
    var line: String {
        let bailWord = bails == 1 ? "bail" : "bails"
        var parts = ["📊 Score \(score)", "\(TimeFormat.short(focusSeconds)) focused",
                     "\(prioritiesDone)/\(prioritiesTotal) priorities", "\(bails) \(bailWord)"]
        if blockedAttempts > 0 { parts.append("\(blockedAttempts) blocked") }
        if closedTabs > 0 { parts.append("\(closedTabs) \(closedTabs == 1 ? "tab" : "tabs") closed") }
        return parts.joined(separator: " · ")
    }

    /// Sessions that count for `day` (`DayKey`, so a day runs from 4 AM): ended, and not demo data.
    static func summarize(day: String, sessions: [Session], priorities: [Priority],
                          calendar: Calendar = .current) -> DaySummary {
        let todays = sessions.filter { session in
            session.end != nil && !session.isDemo && DayKey.key(for: session.start, calendar: calendar) == day
        }
        return DaySummary(focusSeconds: todays.reduce(0) { $0 + $1.duration },
                          sessionCount: todays.count,
                          bails: todays.filter { $0.outcome == .bailed }.count,
                          blockedAttempts: todays.reduce(0) { $0 + $1.blockedAttempts },
                          closedTabs: todays.reduce(0) { $0 + $1.closedTabs },
                          prioritiesDone: priorities.filter(\.isDone).count,
                          prioritiesTotal: priorities.count)
    }
}

extension DiscordMessages {
    /// 🌙 recap posted when the day is wrapped up, with the day's score on the second line.
    static func dayRecap(name: String, done: [String], notDone: [String], tomorrow: [String],
                         summary: DaySummary) -> String {
        func list(_ items: [String]) -> String { items.isEmpty ? "—" : items.joined(separator: " · ") }
        return [
            "🌙 **\(name)** wrapped up the day",
            summary.line,
            "✅ Done: \(list(done))",
            "❌ Not done: \(list(notDone))",
            "📅 Tomorrow: \(list(tomorrow))",
        ].joined(separator: "\n")
    }
}
