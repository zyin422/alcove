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

    /// Returns the seconds remaining until the night guard lifts at 4 AM, or 0 if not currently past midnight.
    static func bedtimeSecondsRemaining(now: Date, calendar: Calendar = .current) -> TimeInterval {
        guard isPastMidnight(now: now, calendar: calendar) else { return 0 }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = DayKey.dayStartHour
        components.minute = 0
        components.second = 0
        guard let deadline = calendar.date(from: components) else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// True when the bedtime guard should lock the screen:
    /// It is past midnight (00:00 - 03:59), bedtime guard is enabled, and no active work block is in progress.
    static func shouldShowBedtime(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool = false,
                                  calendar: Calendar = .current) -> Bool {
        guard settings.bedtimeGuardEnabled, !isLocked, !isBusy else { return false }
        return isPastMidnight(now: now, calendar: calendar)
    }

    /// Returns the upcoming 12:00 AM Date if `now` is within the final 60-minute wind-down (`23:00–23:59`)
    /// and `bedtimeGuardEnabled` is true, or nil otherwise.
    static func nextMidnightBedtime(after now: Date, bedtimeGuardEnabled: Bool,
                                    calendar: Calendar = .current) -> Date? {
        guard bedtimeGuardEnabled else { return nil }
        let hour = calendar.component(.hour, from: now)
        guard hour == 23 else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday)
    }

    /// Seconds remaining until 12:00 AM bedtime lock during the `23:00–23:59` wind-down window.
    static func secondsUntilMidnightBedtime(now: Date, bedtimeGuardEnabled: Bool,
                                            calendar: Calendar = .current) -> TimeInterval? {
        guard let midnight = nextMidnightBedtime(after: now, bedtimeGuardEnabled: bedtimeGuardEnabled, calendar: calendar) else {
            return nil
        }
        return max(0, midnight.timeIntervalSince(now))
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
    /// is wrapped up or all study subjects for the day are completed. A calendar event and the grace after a real block both keep it down.
    static func morningPrompt(now: Date, settings: AppSettings, isLocked: Bool, isBusy: Bool, wrappedUp: Bool,
                              studyCompleted: Bool = false,
                              sessions: [Session], quiet: [QuietInterval], graceUntil: Date?, graceHeld: Bool,
                              calendar: Calendar = .current) -> MorningPrompt {
        let down = MorningPrompt(show: false, waitUntil: nil, postponeAllowed: false, graceUntil: nil)
        guard settings.morningScreenEnabled, !isLocked, !graceHeld else { return down }
        if isBusy { return down }
        if wrappedUp || studyCompleted {
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
                                  studyCompleted: Bool = false,
                                  calendar: Calendar = .current) -> Bool {
        var settings = settings
        if let postponeUntil { settings.morningPostponeUntil = postponeUntil }
        let sessions = hasStartedBlock
            ? [Session(subjectID: UUID(), subjectName: "", mode: .open, start: now)]
            : []
        return morningPrompt(now: now, settings: settings, isLocked: isLocked, isBusy: isBusy, wrappedUp: false,
                             studyCompleted: studyCompleted,
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

    /// The next unfinished priority in `plan`, optionally excluding an in-flight or just-confirmed priority ID.
    static func nextPriority(in plan: DayPlan?, excludingID: UUID? = nil) -> Priority? {
        guard let plan else { return nil }
        return plan.priorities.first { !$0.isDone && $0.id != excludingID }
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
                if result[match].estimatedMinutes == nil { result[match].estimatedMinutes = priority.estimatedMinutes }
            } else {
                result.append(priority)
            }
        }
        return result
    }

    /// Prepares unfinished priorities for rollover into tomorrow with clean uncompleted state.
    static func prepareRollover(from priorities: [Priority], selectedIDs: Set<UUID>) -> [Priority] {
        priorities
            .filter { selectedIDs.contains($0.id) && !$0.isDone }
            .map { priority in
                Priority(
                    title: priority.title,
                    subjectID: priority.subjectID,
                    isDone: false,
                    googleTaskID: priority.googleTaskID,
                    estimatedMinutes: priority.estimatedMinutes,
                    scheduledMinutesFromMidnight: nil,
                    isAnchor: priority.isAnchor
                )
            }
    }

    /// Merges base tomorrow priorities with checked rollover priorities and queued parked thoughts,
    /// parsing `#subject` hashtags and time estimates on parked thoughts and auto-filling unassigned setups.
    static func buildTomorrowReviewList(
        base: [Priority],
        rolloverSource: [Priority],
        selectedRolloverIDs: Set<UUID>,
        parkedThoughts: [String],
        subjects: [Subject]
    ) -> [Priority] {
        let convertedThoughts = parkedThoughts
            .sorted()
            .map { ThoughtParkingEngine.promoteThoughtToPriority(thought: $0, subjects: subjects) }
        let rollover = prepareRollover(from: rolloverSource, selectedIDs: selectedRolloverIDs)
        let withThoughts = appendNew(convertedThoughts, to: base)
        let merged = appendNew(rollover, to: withThoughts)
        return fillingUnassignedSetups(merged, subjects: subjects)
    }

    /// Parses inline duration/schedule hints (e.g. "Finish MP3 45m") on reviewed priorities
    /// without erasing explicit estimates or assigned setups.
    static func normalizingReviewPriorities(_ priorities: [Priority], subjects: [Subject]) -> [Priority] {
        let filled = fillingUnassignedSetups(priorities, subjects: subjects)
        return filled.map { priority in
            var normalized = priority
            let (cleanedTitle, parsedEst, parsedSched) = parsePriorityDetails(from: priority.title)
            if !cleanedTitle.isEmpty {
                normalized.title = cleanedTitle
            }
            if normalized.estimatedMinutes == nil, let parsedEst {
                normalized.estimatedMinutes = parsedEst
            }
            if normalized.scheduledMinutesFromMidnight == nil, let parsedSched {
                normalized.scheduledMinutesFromMidnight = parsedSched
            }
            if normalized.subjectID == nil {
                normalized.subjectID = matchSubject(normalized.title, subjects: subjects)
            }
            return normalized
        }
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

    /// Matches `title` to the best subject setup:
    /// 1) exact whole-word setup name match (tolerating optional course-code whitespace like "CS 173" for "CS173"),
    /// 2) academic course-code department keyword match (e.g. "LING100" <- "Linguistics ..."),
    /// 3) whole-word keyword overlap against `subject.details`.
    static func matchSubject(_ title: String, subjects: [Subject]) -> UUID? {
        let lowered = title.lowercased()
        let exact = subjects
            .filter { subject in
                let name = subject.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !name.isEmpty else { return false }
                let escaped = NSRegularExpression.escapedPattern(for: name)
                // Allow optional whitespace between leading course letters and digits (e.g. "LING100" matches "LING 100").
                let flexCourse = escaped.replacingOccurrences(
                    of: #"^([a-z]{2,})(\d+[a-z]?)$"#,
                    with: #"$1\\s*$2"#,
                    options: .regularExpression
                )
                let pattern = #"(?<![\p{L}\p{N}])"# + flexCourse + #"(?![\p{L}\p{N}])"#
                return lowered.range(of: pattern, options: .regularExpression) != nil
            }
            .max { $0.name.count < $1.name.count }?
            .id
        if let exact { return exact }

        let titleWords = tokenSet(in: lowered)
        guard !titleWords.isEmpty else { return nil }

        // 2) Course-code department prefix keywords (only when name is letters + digits like LING100).
        if let courseMatch = subjects.compactMap({ subject -> (id: UUID, score: Int)? in
            let code = subject.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let dept = courseDepartmentPrefix(from: code),
                  let keywords = Self.courseDepartmentKeywords[dept] else { return nil }
            let hits = keywords.filter { kw in
                kw.contains(" ") ? lowered.contains(kw) : titleWords.contains(kw)
            }.count
            return hits > 0 ? (subject.id, hits) : nil
        }).max(by: { $0.score < $1.score })?.id {
            return courseMatch
        }

        // 3) Subject.details keyword overlap (ignores stopwords and short tokens).
        return subjects.compactMap { subject -> (id: UUID, score: Int, length: Int)? in
            let keywords = detailKeywords(in: subject.details)
            let matched = keywords.filter { titleWords.contains($0) }
            guard !matched.isEmpty else { return nil }
            let totalLen = matched.reduce(0) { $0 + $1.count }
            return (subject.id, matched.count, totalLen)
        }
        .max { ($0.score, $0.length) < ($1.score, $1.length) }?
        .id
    }

    private static let courseDepartmentKeywords: [String: [String]] = [
        "ling": ["linguistics", "linguistic", "phonetics", "phonology", "syntax", "morphology", "semantics", "pragmatics"],
        "cs": ["computer science", "programming", "software", "algorithms", "data structures"],
        "phys": ["physics", "mechanics", "electromagnetism", "quantum", "thermodynamics"],
        "chem": ["chemistry", "organic", "inorganic", "stoichiometry", "biochem", "biochemistry"],
        "bio": ["biology", "biological", "genetics", "cellular", "anatomy", "ecology"],
        "biol": ["biology", "biological", "genetics", "cellular", "anatomy", "ecology"],
        "psyc": ["psychology", "psychological", "cognitive", "neuroscience", "behavioral"],
        "psych": ["psychology", "psychological", "cognitive", "neuroscience", "behavioral"],
        "econ": ["economics", "economic", "microeconomics", "macroeconomics", "econometrics"],
        "stat": ["statistics", "statistical", "probability", "regression"],
        "hist": ["history", "historical"],
        "phil": ["philosophy", "philosophical", "ethics", "epistemology", "metaphysics"],
        "anth": ["anthropology", "anthropological"],
        "soc": ["sociology", "sociological"],
        "pols": ["political science", "politics", "government"],
        "engl": ["english", "literature", "rhetoric", "composition"],
        "geog": ["geography", "geographical"],
        "astr": ["astronomy", "astrophysics"],
        "geol": ["geology", "geological"],
        "neur": ["neuroscience", "neural"],
        "neuro": ["neuroscience", "neural"],
        "ece": ["electrical engineering", "computer engineering", "circuits", "signals"],
    ]

    private static let detailStopwords: Set<String> = [
        "about", "after", "also", "been", "being", "class", "course", "during", "each", "focus",
        "from", "have", "here", "into", "introductory", "just", "learn", "learning", "like",
        "more", "most", "notes", "only", "other", "over", "practice", "review", "self", "some",
        "study", "studying", "subject", "that", "their", "them", "then", "there", "these", "this",
        "through", "using", "what", "when", "where", "which", "while", "with", "work", "working", "your",
    ]

    private static func courseDepartmentPrefix(from code: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^([a-z]{2,6})\s*\d+[a-z]?$"#),
              let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
              let range = Range(match.range(at: 1), in: code) else { return nil }
        return String(code[range])
    }

    private static func tokenSet(in lowercased: String) -> Set<String> {
        let parts = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { !$0.isEmpty })
    }

    private static func detailKeywords(in details: String) -> Set<String> {
        let words = tokenSet(in: details.lowercased())
        return Set(words.filter { $0.count >= 4 && !detailStopwords.contains($0) })
    }

    /// Auto-assigns a setup as the user types `title`, preserving any manual override or AI-chosen setup.
    static func autoAssignedSubject(
        for title: String,
        currentSubjectID: UUID?,
        lastAutoMatchedID: UUID?,
        userOverrode: Bool,
        subjects: [Subject]
    ) -> (subjectID: UUID?, autoMatchedID: UUID?) {
        guard !userOverrode else { return (currentSubjectID, lastAutoMatchedID) }
        guard currentSubjectID == nil || currentSubjectID == lastAutoMatchedID else {
            return (currentSubjectID, lastAutoMatchedID)
        }
        let matched = matchSubject(title, subjects: subjects)
        return (matched, matched)
    }

    /// Fills any missing setup IDs on `priorities` using `matchSubject`.
    static func fillingUnassignedSetups(_ priorities: [Priority], subjects: [Subject]) -> [Priority] {
        priorities.map { priority in
            guard priority.subjectID == nil else { return priority }
            var copy = priority
            copy.subjectID = matchSubject(priority.title, subjects: subjects)
            return copy
        }
    }

    /// Local fallback for `PriorityExtractor`: split the words and match setups by name.
    static func localPriorities(from text: String, subjects: [Subject]) -> [Priority] {
        splitSpokenList(text).map { item in
            let (clean, estimatedMinutes, scheduledMinutes) = parsePriorityDetails(from: item)
            return Priority(title: clean,
                            subjectID: matchSubject(clean, subjects: subjects),
                            estimatedMinutes: estimatedMinutes,
                            scheduledMinutesFromMidnight: scheduledMinutes)
        }
    }

    /// Extracts both scheduled time and estimated duration from a priority string.
    /// Handles e.g. "8am CS128 lab 45m", "9:30 AM SST Research 2h", "at 2pm Discrete HW 1h".
    static func parsePriorityDetails(from raw: String) -> (title: String, estimatedMinutes: Int?, scheduledMinutes: Int?) {
        let (afterEstTitle, estimatedMinutes) = parseTimeEstimate(from: raw)
        let (finalTitle, scheduledMinutes) = parseScheduledTime(from: afterEstTitle)
        return (finalTitle, estimatedMinutes, scheduledMinutes)
    }

    /// Extracts scheduled start time from a title string, returning cleaned title and minutes from midnight (0..1439).
    /// Handles e.g. "8am", "8:30am", "9:00 AM", "at 2pm", "14:30", "11:45 PM".
    static func parseScheduledTime(from raw: String) -> (title: String, scheduledMinutes: Int?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (title: raw, scheduledMinutes: nil) }

        // Pattern 1: 12-hour format with AM/PM (e.g. "8am", "8:30am", "9:00 AM", "at 2pm", "(10pm)")
        let amPmPattern = #"(?i)(?:\b|at\s+)?(?:\(?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\)?)(?:\s|$|[),.]|\b)"#
        if let regex = try? NSRegularExpression(pattern: amPmPattern) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let hourRange = match.range(at: 1)
                let minRange = match.range(at: 2)
                let amPmRange = match.range(at: 3)
                if hourRange.location != NSNotFound, amPmRange.location != NSNotFound,
                   var hour = Int(nsString.substring(with: hourRange)) {
                    let min = (minRange.location != NSNotFound) ? (Int(nsString.substring(with: minRange)) ?? 0) : 0
                    let amPm = nsString.substring(with: amPmRange).lowercased()
                    if amPm == "pm" && hour < 12 { hour += 12 }
                    if amPm == "am" && hour == 12 { hour = 0 }
                    let totalMinutes = hour * 60 + min
                    let clean = regex.stringByReplacingMatches(in: text, options: [], range: match.range, withTemplate: " ")
                    let trimmed = clean.replacingOccurrences(of: #"(?i)\bat\s*$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:,()")))
                    return (title: trimmed.isEmpty ? raw : trimmed, scheduledMinutes: totalMinutes)
                }
            }
        }

        // Pattern 2: 24-hour format (e.g. "14:30", "09:00", "at 16:45")
        let h24Pattern = #"(?i)(?:^|\s|at\s+)(\d{1,2}):(\d{2})(?:\s|$|[),.]|\b)"#
        if let regex = try? NSRegularExpression(pattern: h24Pattern) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let hourRange = match.range(at: 1)
                let minRange = match.range(at: 2)
                if hourRange.location != NSNotFound, minRange.location != NSNotFound,
                   let hour = Int(nsString.substring(with: hourRange)),
                   let min = Int(nsString.substring(with: minRange)),
                   hour >= 0 && hour < 24 && min >= 0 && min < 60 {
                    let totalMinutes = hour * 60 + min
                    let clean = regex.stringByReplacingMatches(in: text, options: [], range: match.range, withTemplate: " ")
                    let trimmed = clean.replacingOccurrences(of: #"(?i)\bat\s*$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:,()")))
                    return (title: trimmed.isEmpty ? raw : trimmed, scheduledMinutes: totalMinutes)
                }
            }
        }

        return (title: text, scheduledMinutes: nil)
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

    // MARK: - Unified Day Schedule

    /// Computes the unified daily schedule layout combining Google Calendar events, planned priority blocks,
    /// and completed focus sessions. Unscheduled priorities are slotted into open calendar gaps.
    static func computeScheduleLayout(
        day: String,
        calendarEvents: [GoogleEvent],
        priorities: [Priority],
        sessions: [Session],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DayScheduleLayout {
        var calBlocks: [ScheduleBlock] = []
        for event in calendarEvents {
            guard let s = event.start.parsed, let e = event.end.parsed, e > s else { continue }
            let sH = calendar.component(.hour, from: s)
            let sM = calendar.component(.minute, from: s)
            let eH = calendar.component(.hour, from: e)
            let eM = calendar.component(.minute, from: e)
            let startMin = sH * 60 + sM
            let endMin = max(startMin + 5, eH * 60 + eM)
            calBlocks.append(ScheduleBlock(
                id: "cal-\(event.id)",
                kind: .calendarEvent(summary: event.summary ?? "Calendar event"),
                startMinutes: startMin,
                endMinutes: endMin,
                title: event.summary ?? "Calendar event",
                subjectID: nil,
                isDone: true
            ))
        }

        var sessBlocks: [ScheduleBlock] = []
        for session in sessions {
            guard !session.isDemo && session.duration > 0 else { continue }
            let sH = calendar.component(.hour, from: session.start)
            let sM = calendar.component(.minute, from: session.start)
            let startMin = sH * 60 + sM
            let durMin = max(1, Int(session.duration / 60))
            let endMin = startMin + durMin
            sessBlocks.append(ScheduleBlock(
                id: "sess-\(session.id.uuidString)",
                kind: .completedSession(sessionID: session.id, subjectName: session.subjectName, subjectID: session.subjectID, duration: session.duration),
                startMinutes: startMin,
                endMinutes: endMin,
                title: session.subjectName,
                subjectID: session.subjectID,
                isDone: true
            ))
        }

        var minHour = 7.0
        var maxHour = 23.0
        let allMinutes = (calBlocks + sessBlocks).flatMap { [$0.startMinutes, $0.endMinutes] }
        if let earliest = allMinutes.min(), Double(earliest) / 60.0 < minHour {
            minHour = max(4.0, floor(Double(earliest) / 60.0))
        }
        if let latest = allMinutes.max(), Double(latest) / 60.0 > maxHour {
            maxHour = min(28.0, ceil(Double(latest) / 60.0))
        }

        var plannedBlocks: [ScheduleBlock] = []
        let busySpans = calBlocks.map { ($0.startMinutes, $0.endMinutes) }.sorted { $0.0 < $1.0 }

        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (nowParts.hour ?? Int(minHour)) * 60 + (nowParts.minute ?? 0)
        var cursor = max(Int(minHour * 60), min(nowMinutes, Int((maxHour - 2) * 60)))

        for priority in priorities {
            let dur = priority.estimatedMinutes ?? 45
            if let explicitStart = priority.scheduledMinutesFromMidnight {
                let pEnd = explicitStart + dur
                let conflict = calBlocks.first { cal in
                    max(explicitStart, cal.startMinutes) < min(pEnd, cal.endMinutes)
                }
                plannedBlocks.append(ScheduleBlock(
                    id: "plan-\(priority.id.uuidString)",
                    kind: .plannedPriority(priorityID: priority.id, title: priority.title, subjectID: priority.subjectID, isDone: priority.isDone),
                    startMinutes: explicitStart,
                    endMinutes: pEnd,
                    title: priority.title,
                    subjectID: priority.subjectID,
                    isDone: priority.isDone,
                    hasConflict: conflict != nil,
                    conflictingEventTitle: conflict?.title
                ))
            } else {
                var candidate = cursor
                var placed = false
                while candidate + dur <= Int(maxHour * 60) {
                    let candidateEnd = candidate + dur
                    let collision = busySpans.first { span in
                        max(candidate, span.0) < min(candidateEnd, span.1)
                    }
                    if let collision {
                        candidate = collision.1 + 10
                    } else {
                        plannedBlocks.append(ScheduleBlock(
                            id: "plan-\(priority.id.uuidString)",
                            kind: .plannedPriority(priorityID: priority.id, title: priority.title, subjectID: priority.subjectID, isDone: priority.isDone),
                            startMinutes: candidate,
                            endMinutes: candidateEnd,
                            title: priority.title,
                            subjectID: priority.subjectID,
                            isDone: priority.isDone
                        ))
                        cursor = candidateEnd + 15
                        placed = true
                        break
                    }
                }
                if !placed {
                    let pEnd = cursor + dur
                    let conflict = calBlocks.first { cal in
                        max(cursor, cal.startMinutes) < min(pEnd, cal.endMinutes)
                    }
                    plannedBlocks.append(ScheduleBlock(
                        id: "plan-\(priority.id.uuidString)",
                        kind: .plannedPriority(priorityID: priority.id, title: priority.title, subjectID: priority.subjectID, isDone: priority.isDone),
                        startMinutes: cursor,
                        endMinutes: pEnd,
                        title: priority.title,
                        subjectID: priority.subjectID,
                        isDone: priority.isDone,
                        hasConflict: conflict != nil,
                        conflictingEventTitle: conflict?.title
                    ))
                    cursor += dur + 15
                }
            }
        }

        let all = (calBlocks + plannedBlocks + sessBlocks).sorted {
            if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
            return $0.endMinutes < $1.endMinutes
        }

        return DayScheduleLayout(
            day: day,
            dayStartHour: minHour,
            dayEndHour: maxHour,
            calendarBlocks: calBlocks.sorted { $0.startMinutes < $1.startMinutes },
            plannedBlocks: plannedBlocks.sorted { $0.startMinutes < $1.startMinutes },
            sessionBlocks: sessBlocks.sorted { $0.startMinutes < $1.startMinutes },
            chronologicalAgenda: all
        )
    }

    /// Computes uninterrupted open deep-work windows (`>= minimumMinutes`) between calendar events
    /// during the active day (`7:00 AM – 11:00 PM` by default), clipping past time when `isToday` is true.
    static func availableFocusWindows(
        calendarEvents: [GoogleEvent],
        dayStartMinutes: Int = 7 * 60,
        dayEndMinutes: Int = 23 * 60,
        minimumMinutes: Int = 25,
        now: Date = Date(),
        isToday: Bool = true,
        calendar: Calendar = .current
    ) -> [OpenFocusWindow] {
        guard dayEndMinutes > dayStartMinutes else { return [] }
        var effectiveStart = dayStartMinutes
        if isToday {
            let parts = calendar.dateComponents([.hour, .minute], from: now)
            let nowMins = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            // Round current minute up to nearest 5-minute mark for crisp scheduling labels.
            let roundedNow = ((nowMins + 4) / 5) * 5
            effectiveStart = max(dayStartMinutes, roundedNow)
        }
        guard effectiveStart + minimumMinutes <= dayEndMinutes else { return [] }

        var busy: [(start: Int, end: Int)] = []
        for event in calendarEvents {
            guard let s = event.start.parsed, let e = event.end.parsed, e > s else { continue }
            let sParts = calendar.dateComponents([.hour, .minute], from: s)
            let eParts = calendar.dateComponents([.hour, .minute], from: e)
            let startMin = (sParts.hour ?? 0) * 60 + (sParts.minute ?? 0)
            let endMin = max(startMin + 5, (eParts.hour ?? 0) * 60 + (eParts.minute ?? 0))
            let clampedStart = max(effectiveStart, startMin)
            let clampedEnd = min(dayEndMinutes, endMin)
            if clampedEnd > clampedStart {
                busy.append((clampedStart, clampedEnd))
            }
        }
        busy.sort { $0.start < $1.start }

        var merged: [(start: Int, end: Int)] = []
        for interval in busy {
            if var last = merged.last, interval.start <= last.end {
                last.end = max(last.end, interval.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }

        var windows: [OpenFocusWindow] = []
        var cursor = effectiveStart
        for interval in merged {
            if interval.start - cursor >= minimumMinutes {
                windows.append(OpenFocusWindow(startMinutes: cursor, endMinutes: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if dayEndMinutes - cursor >= minimumMinutes {
            windows.append(OpenFocusWindow(startMinutes: cursor, endMinutes: dayEndMinutes))
        }
        return windows
    }
}

// MARK: - Schedule Types

struct OpenFocusWindow: Identifiable, Equatable {
    let startMinutes: Int
    let endMinutes: Int

    var id: String { "\(startMinutes)-\(endMinutes)" }
    var durationMinutes: Int { max(0, endMinutes - startMinutes) }

    /// Standard focus length recommendation fitting inside this window (90m, 50m, 25m, or clamped gap).
    var suggestedBlockMinutes: Int {
        if durationMinutes >= 90 { return 90 }
        if durationMinutes >= 50 { return 50 }
        if durationMinutes >= 25 { return 25 }
        return LockInOption.clampedMinutes(durationMinutes)
    }

    var timeRangeLabel: String {
        "\(Self.formatMinutes(startMinutes)) – \(Self.formatMinutes(endMinutes))"
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let period = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return m == 0 ? "\(displayH) \(period)" : String(format: "%d:%02d %@", displayH, m, period)
    }
}

enum ScheduleBlockKind: Equatable {
    case calendarEvent(summary: String)
    case plannedPriority(priorityID: UUID, title: String, subjectID: UUID?, isDone: Bool)
    case completedSession(sessionID: UUID, subjectName: String, subjectID: UUID, duration: TimeInterval)
}

struct ScheduleBlock: Identifiable, Equatable {
    var id: String
    var kind: ScheduleBlockKind
    var startMinutes: Int
    var endMinutes: Int
    var title: String
    var subjectID: UUID?
    var isDone: Bool
    var hasConflict: Bool = false
    var conflictingEventTitle: String? = nil

    var durationMinutes: Int {
        max(1, endMinutes - startMinutes)
    }

    var timeRangeLabel: String {
        let sH = (startMinutes / 60) % 24
        let sM = startMinutes % 60
        let sP = sH >= 12 ? "PM" : "AM"
        let sDH = sH == 0 ? 12 : (sH > 12 ? sH - 12 : sH)
        let sStr = sM == 0 ? "\(sDH) \(sP)" : String(format: "%d:%02d %@", sDH, sM, sP)

        let eH = (endMinutes / 60) % 24
        let eM = endMinutes % 60
        let eP = eH >= 12 ? "PM" : "AM"
        let eDH = eH == 0 ? 12 : (eH > 12 ? eH - 12 : eH)
        let eStr = eM == 0 ? "\(eDH) \(eP)" : String(format: "%d:%02d %@", eDH, eM, eP)
        return "\(sStr) – \(eStr)"
    }
}

struct DayScheduleLayout: Equatable {
    var day: String
    var dayStartHour: Double
    var dayEndHour: Double
    var calendarBlocks: [ScheduleBlock]
    var plannedBlocks: [ScheduleBlock]
    var sessionBlocks: [ScheduleBlock]
    var chronologicalAgenda: [ScheduleBlock]

    var totalSpanHours: Double {
        max(1.0, dayEndHour - dayStartHour)
    }

    func fractions(startMinutes: Int, endMinutes: Int) -> (start: CGFloat, duration: CGFloat) {
        let startH = Double(startMinutes) / 60.0
        let endH = Double(endMinutes) / 60.0
        let clampedStart = max(dayStartHour, min(dayEndHour, startH))
        let clampedEnd = max(dayStartHour, min(dayEndHour, endH))
        let startF = CGFloat((clampedStart - dayStartHour) / totalSpanHours)
        let durationF = CGFloat(max(0.005, (clampedEnd - clampedStart) / totalSpanHours))
        return (startF, durationF)
    }

    func currentFraction(now: Date = Date(), calendar: Calendar = .current) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowH = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60.0
        guard nowH >= dayStartHour && nowH <= dayEndHour else { return -1 }
        return CGFloat((nowH - dayStartHour) / totalSpanHours)
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
