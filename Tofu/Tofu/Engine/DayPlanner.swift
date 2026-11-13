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

    /// True when the current local time is past midnight but before the new day starts at 4 AM (00:00 - 03:59).
    static func isPastMidnight(now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= 0 && hour < DayKey.dayStartHour
    }

    /// True when the bedtime guard should lock the screen:
    /// It is past midnight (00:00 - 03:59), bedtime guard is enabled, and no active work block is in progress.
    static func shouldShowBedtime(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool = false,
                                  calendar: Calendar = .current) -> Bool {
        guard settings.bedtimeGuardEnabled, !isLocked, !isBusy else { return false }
        return isPastMidnight(now: now, calendar: calendar)
    }

    /// A finished block shorter than this does not count. The screen comes straight back.
    static let realBlockSeconds: TimeInterval = 5 * 60
    /// Quiet time after a real block, so a walk to another room is not treated as wandering off.
    static let betweenBlockGrace: TimeInterval = 20 * 60

    /// A timed calendar event. All-day events are left out: one of those would hide the screen for the whole day.
    struct QuietInterval: Equatable {
        var start: Date
        var end: Date
    }

    /// What the morning screen should do at `now`.
    struct MorningPrompt: Equatable {
        var show: Bool
        /// Check again then. Nil when nothing is waiting.
        var waitUntil: Date?
        /// The one "Start in 10 minutes" is still available.
        var postponeAllowed: Bool
        /// Grace deadline to store. Nil when this check does not change it.
        var graceUntil: Date?
    }

    static func quietIntervals(_ events: [GoogleEvent]) -> [QuietInterval] {
        events.compactMap { event in
            guard let start = event.start.parsed, let end = event.end.parsed, end > start else { return nil }
            return QuietInterval(start: start, end: end)
        }
    }

    /// The morning screen comes back until a real block is under way, and again after one ends, until the day
    /// is wrapped up. A calendar event and the grace after a real block both keep it down.
    static func morningPrompt(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool, wrappedUp: Bool,
                              sessions: [Session], quiet: [QuietInterval], graceUntil: Date?, graceHeld: Bool,
                              calendar: Calendar = .current) -> MorningPrompt {
        let down = MorningPrompt(show: false, waitUntil: nil, postponeAllowed: false, graceUntil: nil)
        guard settings.morningScreenEnabled, !isLocked, !graceHeld else { return down }
        if isBusy { return down }
        if wrappedUp {
            return MorningPrompt(show: false, waitUntil: DayKey.nextStart(after: now, calendar: calendar),
                                 postponeAllowed: false, graceUntil: nil)
        }
        let today = DayKey.key(for: now, calendar: calendar)
        let todays = sessions.filter {
            !$0.isDemo && $0.end != nil && DayKey.key(for: $0.start, calendar: calendar) == today
        }
        let live = sessions.contains {
            !$0.isDemo && $0.end == nil && DayKey.key(for: $0.start, calendar: calendar) == today
        }
        if live { return down }
        let postponeAllowed = settings.lastPostponeKey != today
        // If the user clicked "Not now", keep the screen down until the 10-minute delay expires.
        if let postpone = settings.morningPostponeUntil, postpone > now {
            return MorningPrompt(show: false, waitUntil: postpone, postponeAllowed: false, graceUntil: nil)
        }
        let covering = quiet.first { $0.start <= now && now < $0.end }
        guard let latest = todays.max(by: { ($0.end ?? $0.start) < ($1.end ?? $1.start) }) else {
            if let covering {
                return MorningPrompt(show: false, waitUntil: covering.end, postponeAllowed: postponeAllowed,
                                     graceUntil: nil)
            }
            guard DayKey.minutesIntoDay(now, calendar: calendar) < settings.dayEndMinutes else { return down }
            return MorningPrompt(show: true, waitUntil: nil, postponeAllowed: postponeAllowed, graceUntil: nil)
        }
        if latest.duration < realBlockSeconds {
            if let covering {
                return MorningPrompt(show: false, waitUntil: covering.end, postponeAllowed: postponeAllowed, graceUntil: nil)
            }
            return MorningPrompt(show: true, waitUntil: nil, postponeAllowed: postponeAllowed, graceUntil: nil)
        }
        let end = latest.end ?? now
        var deadline = graceUntil ?? end.addingTimeInterval(betweenBlockGrace)
        if let covering {
            deadline = max(deadline, covering.end.addingTimeInterval(betweenBlockGrace))
        }
        if now < deadline {
            return MorningPrompt(show: false, waitUntil: deadline, postponeAllowed: postponeAllowed, graceUntil: deadline)
        }
        return MorningPrompt(show: true, waitUntil: nil, postponeAllowed: postponeAllowed, graceUntil: deadline)
    }

    /// True when the morning screen should show now: it is on, no work block is in progress, a "Start in 10
    /// minutes" delay is not still running, and the end-of-day time has not come yet.
    static func shouldShowMorning(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool,
                                  hasStartedBlock: Bool = false, postponeUntil: Date? = nil,
                                  calendar: Calendar = .current) -> Bool {
        var settings = settings
        if let postponeUntil { settings.morningPostponeUntil = postponeUntil }
        let sessions = hasStartedBlock
            ? [Session(subjectID: UUID(), subjectName: "", mode: .open, start: now)]
            : []
        return morningPrompt(now: now, settings: settings, isLocked: isLocked, isBusy: isBusy, wrappedUp: false,
                             sessions: sessions, quiet: [], graceUntil: nil, graceHeld: false, calendar: calendar).show
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

    // MARK: Wrap-up merges (Google-safe: none of these ever drops a stored priority)

    /// The sheet's ticks over the stored plan; stored titles and links win, unseen linked priorities are kept.
    static func mergeWrapUp(snapshot: [Priority], into current: [Priority]) -> [Priority] {
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotIDs = Set(snapshot.map(\.id))
        let ticked = snapshot.map { priority in
            guard let stored = currentByID[priority.id] else { return priority }
            var merged = priority
            merged.title = stored.title
            merged.googleTaskID = stored.googleTaskID ?? priority.googleTaskID
            return merged
        }
        return ticked + current.filter { !snapshotIDs.contains($0.id) && $0.googleTaskID != nil }
    }

    /// The fresh plan with only the done flips the user made in the sheet (`edited` against `original`).
    static func applyingTicks(edited: [Priority], original: [Priority], to fresh: [Priority]) -> [Priority] {
        let before = Dictionary(original.map { ($0.id, $0.isDone) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(edited.map { ($0.id, $0.isDone) }, uniquingKeysWith: { first, _ in first })
        return fresh.map { priority in
            guard let was = before[priority.id], let now = after[priority.id], was != now else { return priority }
            var ticked = priority
            ticked.isDone = now
            return ticked
        }
    }

    /// Unlinked tomorrow items take the id and link of an unfinished linked today item with the same title.
    static func carryLinks(into tomorrow: [Priority], from today: [Priority]) -> [Priority] {
        var candidates = today.filter { !$0.isDone && $0.googleTaskID != nil }
        return tomorrow.map { priority in
            guard priority.googleTaskID == nil,
                  let index = candidates.firstIndex(where: { normalized($0.title) == normalized(priority.title) })
            else { return priority }
            let source = candidates.remove(at: index)
            var carried = priority
            carried.id = source.id
            carried.googleTaskID = source.googleTaskID
            return carried
        }
    }

    /// `existing` plus the `added` items it lacks (by id, link or unlinked title); held ones only gain a setup.
    static func appendNew(_ added: [Priority], to existing: [Priority]) -> [Priority] {
        var result = existing
        for priority in added {
            let match = result.firstIndex { held in
                held.id == priority.id
                    || (priority.googleTaskID != nil && held.googleTaskID == priority.googleTaskID)
                    || (priority.googleTaskID == nil && normalized(held.title) == normalized(priority.title))
            }
            if let match {
                if result[match].subjectID == nil { result[match].subjectID = priority.subjectID }
            } else {
                result.append(priority)
            }
        }
        return result
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        splitSpokenList(text).map { item in
            let (clean, estimatedMinutes) = parseTimeEstimate(from: item)
            return Priority(title: clean, subjectID: matchSubject(clean, subjects: subjects), estimatedMinutes: estimatedMinutes)
        }
    }

    /// Extracts a time estimate from a priority string, returning the cleaned title and minutes.
    /// Handles "45m", "30 min", "1h", "1.5 hours", "(25m)", "2 hr", etc.
    static func parseTimeEstimate(from raw: String) -> (title: String, estimatedMinutes: Int?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (title: raw, estimatedMinutes: nil) }

        // Look for hours: e.g. "1.5h", "2 hours", "1 hr", "(1h)"
        let hoursPattern = #"(?i)(?:\((?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?))\)|(?:^|\s)(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)(?:\s|$|[),.]))"#
        if let regex = try? NSRegularExpression(pattern: hoursPattern) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let captureRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                if captureRange.location != NSNotFound, let hours = Double(nsString.substring(with: captureRange)) {
                    let minutes = Int(round(hours * 60))
                    let clean = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: " ")
                    let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:,()")))
                    return (title: trimmed.isEmpty ? raw : trimmed, estimatedMinutes: minutes)
                }
            }
        }

        // Look for minutes: e.g. "45m", "30 mins", "25 min", "(50m)"
        let minsPattern = #"(?i)(?:\((?:(\d+)\s*(?:m|min|mins|minutes?))\)|(?:^|\s)(\d+)\s*(?:m|min|mins|minutes?)(?:\s|$|[),.]))"#
        if let regex = try? NSRegularExpression(pattern: minsPattern) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let captureRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                if captureRange.location != NSNotFound, let minutes = Int(nsString.substring(with: captureRange)) {
                    let clean = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: " ")
                    let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:,()")))
                    return (title: trimmed.isEmpty ? raw : trimmed, estimatedMinutes: minutes)
                }
            }
        }

        return (title: text, estimatedMinutes: nil)
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
