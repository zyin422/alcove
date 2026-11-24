import XCTest
@testable import Tofu

final class DayPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Day keys

    func testDayRunsFromFourAMToFourAM() {
        XCTAssertEqual(DayKey.key(for: date(10, 9), calendar: calendar), "2026-10-10")
        XCTAssertEqual(DayKey.key(for: date(11, 1), calendar: calendar), "2026-10-10")
        XCTAssertEqual(DayKey.key(for: date(11, 4), calendar: calendar), "2026-10-11")
        XCTAssertEqual(DayKey.tomorrow(from: date(10, 22), calendar: calendar), "2026-10-11")
        XCTAssertEqual(DayKey.tomorrow(from: date(11, 1), calendar: calendar), "2026-10-11")
    }

    func testWorkingDayStaysOnTheCalendarDay() {
        let now = date(11, 6, 17)
        XCTAssertEqual(DayPlanner.workingDay(now: now, plans: [], calendar: calendar), "2026-10-11")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [DayPlan(day: "2026-10-11", wrappedUp: true)], calendar: calendar),
            "2026-10-11", "wrapping up does not move Today onto the next day")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [
                DayPlan(day: "2026-10-11", wrappedUp: true),
                DayPlan(day: "2026-10-12", wrappedUp: true),
                DayPlan(day: "2026-10-13", priorities: [Priority(title: "Exam")]),
            ], calendar: calendar),
            "2026-10-11")
        XCTAssertEqual(DayKey.next("2026-10-11"), "2026-10-12")
        XCTAssertEqual(DayKey.previous("2026-10-12"), "2026-10-11")
    }

    func testUnwrappedPreviousDayBlocksTheNewDay() {
        let now = date(12, 8)
        let open = DayPlan(day: "2026-10-11", priorities: [Priority(title: "Lab")], wrappedUp: false)
        XCTAssertEqual(DayPlanner.workingDay(now: now, plans: [open], calendar: calendar), "2026-10-11")
        let wrapped = DayPlan(day: "2026-10-11", priorities: [Priority(title: "Lab")], wrappedUp: true)
        let today = DayPlan(day: "2026-10-12", priorities: [Priority(title: "Quiz")])
        XCTAssertEqual(DayPlanner.workingDay(now: now, plans: [wrapped, today], calendar: calendar), "2026-10-12")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [today], calendar: calendar),
            "2026-10-12", "a day with no plan does not need a wrap-up")
    }

    func testMonthGridAndUpcomingDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        let cells = DayCalendar.cells(year: 2026, month: 10, calendar: calendar)
        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(DayCalendar.cells(year: 2026, month: 2, calendar: calendar).count, 42)
        XCTAssertEqual(cells.firstIndex { $0.key == "2026-10-01" }, 4, "October 1 2026 is a Thursday")
        XCTAssertEqual(cells.first?.key, "2026-09-27")
        XCTAssertFalse(cells[0].inMonth)
        XCTAssertTrue(cells.contains { $0.key == "2026-10-31" && $0.inMonth && $0.number == 31 })
        XCTAssertFalse(DayCalendar.isUpcoming("2026-10-13", today: "2026-10-13"))
        XCTAssertFalse(DayCalendar.isUpcoming("2026-10-12", today: "2026-10-13"))
        XCTAssertTrue(DayCalendar.isUpcoming("2026-10-14", today: "2026-10-13"))
        XCTAssertEqual(DayCalendar.shiftMonth(year: 2026, month: 12, by: 1, calendar: calendar).year, 2027)
        XCTAssertEqual(DayCalendar.shiftMonth(year: 2026, month: 12, by: 1, calendar: calendar).month, 1)
        XCTAssertEqual(DayCalendar.shiftMonth(year: 2026, month: 1, by: -1, calendar: calendar).year, 2025)
        XCTAssertEqual(DayCalendar.shiftMonth(year: 2026, month: 1, by: -1, calendar: calendar).month, 12)
        XCTAssertEqual(DayCalendar.weekdayLabels(calendar: calendar).count, 7)
    }

    func testSmallHoursCountAsLateEvening() {
        XCTAssertEqual(DayKey.minutesIntoDay(date(10, 22, 30), calendar: calendar), 22 * 60 + 30)
        XCTAssertEqual(DayKey.minutesIntoDay(date(11, 0, 30), calendar: calendar), 24 * 60 + 30)
    }

    // MARK: End-of-day prompt

    private func shouldPrompt(at now: Date, settings: AppSettings = AppSettings(), plans: [DayPlan] = [],
                              isLocked: Bool = false) -> Bool {
        DayPlanner.shouldPromptEndOfDay(now: now, settings: settings, plans: plans, isLocked: isLocked, calendar: calendar)
    }

    func testPromptsOnceTheEndOfDayTimePasses() {
        XCTAssertFalse(shouldPrompt(at: date(10, 21, 59)))
        XCTAssertTrue(shouldPrompt(at: date(10, 22)))
        XCTAssertTrue(shouldPrompt(at: date(11, 0, 30)))
    }

    func testNoPromptWhileLockedInOffAlreadyPromptedOrWrappedUp() {
        XCTAssertFalse(shouldPrompt(at: date(10, 23), isLocked: true))
        XCTAssertFalse(shouldPrompt(at: date(10, 23), settings: AppSettings(dayEndPromptEnabled: false)))
        XCTAssertFalse(shouldPrompt(at: date(10, 23), settings: AppSettings(lastDayPromptKey: "2026-10-10")))
        XCTAssertFalse(shouldPrompt(at: date(10, 23), plans: [DayPlan(day: "2026-10-10", wrappedUp: true)]))
        XCTAssertTrue(shouldPrompt(at: date(10, 23), settings: AppSettings(lastDayPromptKey: "2026-10-09")))
    }

    // MARK: Priority to confirm

    func testFinishedLockInAsksAboutTheFirstOpenPriorityOfItsSetup() {
        let setup = UUID()
        let done = Priority(title: "Lab 1", subjectID: setup, isDone: true)
        let open = Priority(title: "Lab 2", subjectID: setup)
        let other = Priority(title: "Read", subjectID: UUID())
        let plan = DayPlan(day: "2026-10-10", priorities: [other, done, open])
        var session = Session(subjectID: setup, subjectName: "CS128", mode: .open, start: date(10, 9), outcome: .bailed)
        XCTAssertEqual(DayPlanner.priorityToConfirm(after: session, in: plan), open)
        session.outcome = .interrupted
        XCTAssertNil(DayPlanner.priorityToConfirm(after: session, in: plan))
        session.outcome = .completed
        session.subjectID = UUID()
        XCTAssertNil(DayPlanner.priorityToConfirm(after: session, in: plan))
    }

    func testNextPriorityFindsNextUnfinishedPriorityExcludingCurrent() {
        let p1 = Priority(title: "Problem Set 1", isDone: true)
        let p2 = Priority(title: "Problem Set 2", isDone: false)
        let p3 = Priority(title: "Read Chapter 4", isDone: false)
        let plan = DayPlan(day: "2026-10-10", priorities: [p1, p2, p3])

        // Excluding p2 -> returns p3
        XCTAssertEqual(DayPlanner.nextPriority(in: plan, excludingID: p2.id), p3)

        // Excluding nil -> returns first unfinished (p2)
        XCTAssertEqual(DayPlanner.nextPriority(in: plan, excludingID: nil), p2)

        // All done or excluded -> nil
        let allDonePlan = DayPlan(day: "2026-10-10", priorities: [p1])
        XCTAssertNil(DayPlanner.nextPriority(in: allDonePlan, excludingID: nil))
    }

    // MARK: Spoken list

    func testSplitsASpokenListIntoTitles() {
        XCTAssertEqual(DayPlanner.splitSpokenList("I need to finish the CS128 lab, then review calc and also call mom"),
                       ["Finish the CS128 lab", "Review calc", "Call mom"])
        XCTAssertEqual(DayPlanner.splitSpokenList("1. Problem set 2. Read chapter four"), ["Problem set", "Read chapter four"])
        XCTAssertEqual(DayPlanner.splitSpokenList("  ,, "), [])
    }

    func testCleanTitleDropsFillerAndKeepsTheRest() {
        XCTAssertEqual(DayPlanner.cleanTitle("and tomorrow I want to read and summarize chapter 4."), "Read and summarize chapter 4")
        XCTAssertEqual(DayPlanner.cleanTitle("um "), nil)
    }

    func testMatchSubjectFindsWholeWordNamesPreferringTheLongest() {
        let cs = Subject(name: "CS128")
        let math = Subject(name: "Math")
        let math241 = Subject(name: "Math 241")
        let subjects = [cs, math, math241]
        XCTAssertEqual(DayPlanner.matchSubject("Finish the cs128 lab", subjects: subjects), cs.id)
        XCTAssertEqual(DayPlanner.matchSubject("Review Math 241 chapter 4", subjects: subjects), math241.id)
        XCTAssertNil(DayPlanner.matchSubject("Mathematics reading", subjects: subjects))
        XCTAssertNil(DayPlanner.matchSubject("Call mom", subjects: subjects))
    }

    // MARK: Recap message

    func testDayRecapListsDoneNotDoneAndTomorrow() {
        let summary = DaySummary(focusSeconds: 80 * 60, sessionCount: 1, bails: 0,
                                 blockedAttempts: 0, closedTabs: 0, prioritiesDone: 2, prioritiesTotal: 2)
        XCTAssertEqual(summary.score, Int((50.0).rounded()) + Int((30.0 * 80.0 / 90.0).rounded()) + 20)
        XCTAssertEqual(DiscordMessages.dayRecap(name: "Zixuan", done: ["Lab 2", "Read"], notDone: [],
                                               tomorrow: ["Quiz prep"], summary: summary),
                       "🌙 **Zixuan** wrapped up the day\n\(summary.line)\n✅ Done: Lab 2 · Read\n❌ Not done: —\n📅 Tomorrow: Quiz prep")
    }

    func testScoreRewardsPrioritiesFocusAndNotBailing() {
        let full = DaySummary(focusSeconds: 90 * 60, sessionCount: 2, bails: 0, blockedAttempts: 3, closedTabs: 1,
                              prioritiesDone: 3, prioritiesTotal: 3)
        XCTAssertEqual(full.score, 100)
        XCTAssertEqual(full.line, "📊 Score 100 · 1h 30m focused · 3/3 priorities · 0 bails · 3 blocked · 1 tab closed")

        let bailed = DaySummary(focusSeconds: 20 * 60, sessionCount: 1, bails: 1, blockedAttempts: 0, closedTabs: 2,
                                prioritiesDone: 0, prioritiesTotal: 2)
        XCTAssertEqual(bailed.score, Int((30.0 * 20.0 / 90.0).rounded()))
        XCTAssertTrue(bailed.line.contains("1 bail"))
        XCTAssertTrue(bailed.line.contains("2 tabs closed"))

        XCTAssertEqual(DaySummary.summarize(day: "2026-10-10", sessions: [], priorities: []).score, 0)
    }

    func testSummaryCountsOnlyThisDaysRealSessions() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))!
        let day = DayKey.key(for: start, calendar: calendar)
        func session(minutes: Int, outcome: SessionOutcome, demo: Bool = false, dayOffset: Int = 0) -> Session {
            let begin = start.addingTimeInterval(TimeInterval(dayOffset) * 86400)
            return Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 50), start: begin,
                           end: begin.addingTimeInterval(TimeInterval(minutes * 60)), blockedAttempts: 2, closedTabs: 1,
                           outcome: outcome, isDemo: demo)
        }
        let summary = DaySummary.summarize(day: day, sessions: [
            session(minutes: 40, outcome: .completed),
            session(minutes: 15, outcome: .bailed),
            session(minutes: 100, outcome: .completed, demo: true),
            session(minutes: 30, outcome: .completed, dayOffset: 2),
        ], priorities: [Priority(title: "Lab", isDone: true), Priority(title: "Read")], calendar: calendar)
        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.bails, 1)
        XCTAssertEqual(summary.focusSeconds, 55 * 60, accuracy: 0.1)
        XCTAssertEqual(summary.blockedAttempts, 4)
        XCTAssertEqual(summary.prioritiesDone, 1)
        XCTAssertEqual(summary.prioritiesTotal, 2)
    }

    // MARK: AI reply parsing

    func testParsesTheAIReplyAndMatchesSetupsByName() {
        let cs = Subject(name: "CS128")
        let reply = """
        ```json
        {"priorities":[{"title":"Finish lab 3","setup":"cs128"},{"title":"Call mom","setup":""},{"title":"  ","setup":"x"}]}
        ```
        """
        let parsed = PriorityExtractor.parse(reply, subjects: [cs])
        XCTAssertEqual(parsed?.map(\.title), ["Finish lab 3", "Call mom"])
        XCTAssertEqual(parsed?.map(\.subjectID), [cs.id, nil])
        XCTAssertNil(PriorityExtractor.parse("Sorry, I can't.", subjects: [cs]))
    }

    @MainActor func testExtractorWithoutAKeyFallsBackToLocalSplitting() async {
        let cs = Subject(name: "CS128")
        let extractor = PriorityExtractor(apiKey: { nil })
        let result = await extractor.priorities(from: "CS128 lab, then laundry", subjects: [cs])
        XCTAssertEqual(result.map(\.title), ["CS128 lab", "Laundry"])
        XCTAssertEqual(result.map(\.subjectID), [cs.id, nil])
    }

    @MainActor func testExtractorUsesTheAIReply() async throws {
        let body = MockTransport.json(#"{"choices":[{"message":{"content":"{\"priorities\":[{\"title\":\"Quiz prep\",\"setup\":\"CS128\"}]}"}}]}"#)
        let mock = MockTransport { _ in (200, body) }
        let cs = Subject(name: "CS128")
        let result = await PriorityExtractor(apiKey: { "sk" }, transport: mock).priorities(from: "quiz prep", subjects: [cs])
        XCTAssertEqual(result.map(\.title), ["Quiz prep"])
        XCTAssertEqual(result.first?.subjectID, cs.id)
        XCTAssertEqual(mock.requests.count, 1)
        let sent = String(data: mock.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("json_object"))
    }

    func testConversationPromptUsesUnfinishedWork() {
        let cs = Subject(name: "CS173")
        let prompt = PriorityExtractor.conversationPrompt(unfinished: [Priority(title: "Calc241", subjectID: cs.id)],
                                                          subjects: [cs])
        XCTAssertTrue(prompt.contains("Calc241"))
        XCTAssertTrue(prompt.contains("CS173"))
        XCTAssertTrue(prompt.contains("\"ready\""))
    }

    func testConversationTurnBecomesAListOnlyWhenReady() {
        let cs = Subject(name: "CS173")
        let asking = PriorityExtractor.conversationTurn(
            from: #"{"message":"Calc241 is still open. Is that tomorrow?","ready":false,"priorities":[]}"#,
            subjects: [cs])
        XCTAssertFalse(asking.ready)
        XCTAssertTrue(asking.message.contains("Calc241"))
        let ready = PriorityExtractor.conversationTurn(
            from: #"{"message":"Tomorrow is Calc241.","ready":true,"priorities":[{"title":"Calc241","setup":"CS173"}]}"#,
            subjects: [cs])
        XCTAssertTrue(ready.ready)
        XCTAssertEqual(ready.priorities.map(\.title), ["Calc241"])
        XCTAssertEqual(ready.priorities.map(\.subjectID), [cs.id])
    }

    @MainActor func testConversationUsesTheModel() async {
        let body = MockTransport.json(#"""
        {"choices":[{"message":{"content":"{\"message\":\"Calc241 is still open. Keep it tomorrow?\",\"ready\":false,\"priorities\":[]}"}}]}
        """#)
        let mock = MockTransport { _ in (200, body) }
        let cs = Subject(name: "CS173")
        let turn = await PriorityExtractor(apiKey: { "sk" }, transport: mock)
            .respond(history: [], unfinished: [Priority(title: "Calc241", subjectID: cs.id)], subjects: [cs])
        XCTAssertFalse(turn.ready)
        XCTAssertTrue(turn.message.contains("Calc241"))
        let sent = String(data: mock.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("Calc241"))
        XCTAssertTrue(sent.contains("json_object"))
    }

    @MainActor func testConversationWithoutAKeyDoesNotInventAList() async {
        let turn = await PriorityExtractor(apiKey: { nil }).respond(history: [], unfinished: [], subjects: [])
        XCTAssertFalse(turn.ready)
        XCTAssertEqual(turn.message, "")
    }

    // MARK: Old store files

    func testStoreFileWithoutDayPlansStillLoads() throws {
        let json = #"{"version":1,"subjects":[],"sessions":[],"settings":{"displayName":"Z","discordEnabled":true,"giveUpTemplate":"x","channelCache":{}}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try decoder.decode(StoreData.self, from: Data(json.utf8))
        XCTAssertEqual(data.dayPlans, [])
        XCTAssertEqual(data.settings.displayName, "Z")
        XCTAssertTrue(data.settings.dayEndPromptEnabled)
        XCTAssertEqual(data.settings.dayEndMinutes, 22 * 60)
    }

    // MARK: - Time Slot Parsing & Schedule Layout Tests

    func testParseScheduledTime12HourAmPm() {
        let (t1, m1) = DayPlanner.parseScheduledTime(from: "8am CS128 lab")
        XCTAssertEqual(m1, 8 * 60)
        XCTAssertEqual(t1, "CS128 lab")

        let (t2, m2) = DayPlanner.parseScheduledTime(from: "9:30 AM SST Research")
        XCTAssertEqual(m2, 9 * 60 + 30)
        XCTAssertEqual(t2, "SST Research")

        let (t3, m3) = DayPlanner.parseScheduledTime(from: "at 2pm Discrete HW")
        XCTAssertEqual(m3, 14 * 60)
        XCTAssertEqual(t3, "Discrete HW")

        let (t4, m4) = DayPlanner.parseScheduledTime(from: "Deep work at 11:45 PM")
        XCTAssertEqual(m4, 23 * 60 + 45)
        XCTAssertEqual(t4, "Deep work")

        let (t5, m5) = DayPlanner.parseScheduledTime(from: "12pm Lunch")
        XCTAssertEqual(m5, 12 * 60)
        XCTAssertEqual(t5, "Lunch")

        let (t6, m6) = DayPlanner.parseScheduledTime(from: "12am Midnight Review")
        XCTAssertEqual(m6, 0)
        XCTAssertEqual(t6, "Midnight Review")
    }

    func testParseScheduledTime24Hour() {
        let (t1, m1) = DayPlanner.parseScheduledTime(from: "14:30 Meeting")
        XCTAssertEqual(m1, 14 * 60 + 30)
        XCTAssertEqual(t1, "Meeting")

        let (t2, m2) = DayPlanner.parseScheduledTime(from: "at 09:15 Lab")
        XCTAssertEqual(m2, 9 * 60 + 15)
        XCTAssertEqual(t2, "Lab")
    }

    func testParsePriorityDetailsCombined() {
        let (t1, est1, sched1) = DayPlanner.parsePriorityDetails(from: "8am CS128 lab 45m")
        XCTAssertEqual(t1, "CS128 lab")
        XCTAssertEqual(est1, 45)
        XCTAssertEqual(sched1, 8 * 60)

        let (t2, est2, sched2) = DayPlanner.parsePriorityDetails(from: "SST Research 2h at 9:30 AM")
        XCTAssertEqual(t2, "SST Research")
        XCTAssertEqual(est2, 120)
        XCTAssertEqual(sched2, 9 * 60 + 30)

        let (t3, est3, sched3) = DayPlanner.parsePriorityDetails(from: "Discrete HW 1.5 hours")
        XCTAssertEqual(t3, "Discrete HW")
        XCTAssertEqual(est3, 90)
        XCTAssertNil(sched3)
    }

    func testPriorityScheduledTimeLabel() {
        let p1 = Priority(title: "Lab", estimatedMinutes: 45, scheduledMinutesFromMidnight: 9 * 60)
        XCTAssertEqual(p1.scheduledTimeLabel, "9 AM – 9:45 AM")

        let p2 = Priority(title: "Research", estimatedMinutes: 90, scheduledMinutesFromMidnight: 13 * 60 + 30)
        XCTAssertEqual(p2.scheduledTimeLabel, "1:30 PM – 3 PM")

        let p3 = Priority(title: "Ad hoc", scheduledMinutesFromMidnight: 10 * 60)
        XCTAssertEqual(p3.scheduledTimeLabel, "10 AM")

        let p4 = Priority(title: "Unscheduled", estimatedMinutes: 60)
        XCTAssertNil(p4.scheduledTimeLabel)
    }

    func testPriorityScheduledMinutesCodableBackwardsCompatibility() throws {
        let legacyJSON = """
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"Old task","isDone":false,"estimatedMinutes":45}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Priority.self, from: legacyJSON)
        XCTAssertEqual(decoded.title, "Old task")
        XCTAssertEqual(decoded.estimatedMinutes, 45)
        XCTAssertNil(decoded.scheduledMinutesFromMidnight)

        let newPriority = Priority(title: "Task with schedule", estimatedMinutes: 60, scheduledMinutesFromMidnight: 600)
        let encoded = try JSONEncoder().encode(newPriority)
        let roundtrip = try JSONDecoder().decode(Priority.self, from: encoded)
        XCTAssertEqual(roundtrip.title, "Task with schedule")
        XCTAssertEqual(roundtrip.estimatedMinutes, 60)
        XCTAssertEqual(roundtrip.scheduledMinutesFromMidnight, 600)
    }

    func testComputeScheduleLayoutWithCalendarAndPriorities() {
        let eventStart = date(15, 10, 0)
        let eventEnd = date(15, 11, 0)
        let event = GoogleEvent(
            id: "ev1",
            summary: "Lecture",
            start: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: eventStart), date: nil),
            end: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: eventEnd), date: nil)
        )

        let p1 = Priority(title: "Morning Study", estimatedMinutes: 60, scheduledMinutesFromMidnight: 8 * 60)
        let p2 = Priority(title: "Research", estimatedMinutes: 90)

        let layout = DayPlanner.computeScheduleLayout(
            day: "2026-10-15",
            calendarEvents: [event],
            priorities: [p1, p2],
            sessions: [],
            calendar: calendar,
            now: date(15, 8, 0)
        )

        XCTAssertEqual(layout.calendarBlocks.count, 1)
        XCTAssertEqual(layout.calendarBlocks.first?.startMinutes, 10 * 60)
        XCTAssertEqual(layout.calendarBlocks.first?.endMinutes, 11 * 60)

        XCTAssertEqual(layout.plannedBlocks.count, 2)
        XCTAssertEqual(layout.plannedBlocks[0].startMinutes, 8 * 60)
        XCTAssertEqual(layout.plannedBlocks[0].endMinutes, 9 * 60)

        let p2Block = layout.plannedBlocks[1]
        let overlapsLecture = max(p2Block.startMinutes, 10 * 60) < min(p2Block.endMinutes, 11 * 60)
        XCTAssertFalse(overlapsLecture, "Planned priority must not overlap calendar event")

        XCTAssertFalse(layout.chronologicalAgenda.isEmpty)
        XCTAssertEqual(layout.chronologicalAgenda.count, 3)
    }

    func testDynamicBoundsExpandForEarlyAndLateBlocks() {
        let earlyStart = date(15, 5, 30)
        let earlyEnd = date(15, 6, 30)
        let earlyEvent = GoogleEvent(
            id: "ev_early",
            summary: "Dawn Workout",
            start: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: earlyStart), date: nil),
            end: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: earlyEnd), date: nil)
        )

        let layout = DayPlanner.computeScheduleLayout(
            day: "2026-10-15",
            calendarEvents: [earlyEvent],
            priorities: [],
            sessions: [],
            calendar: calendar,
            now: date(15, 8, 0)
        )

        XCTAssertLessThanOrEqual(layout.dayStartHour, 5.0, "Day start must expand for early morning event")
    }

    func testScheduleConflictDetectionWithCalendarEvent() {
        let calStart = date(15, 14, 0)
        let calEnd = date(15, 15, 0)
        let event = GoogleEvent(
            id: "ev_conflict",
            summary: "Team Sync",
            start: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: calStart), date: nil),
            end: GoogleEventTime(dateTime: ISO8601DateFormatter().string(from: calEnd), date: nil)
        )

        let conflictingPriority = Priority(title: "Deep Work", estimatedMinutes: 60, scheduledMinutesFromMidnight: 14 * 60 + 15)
        let safePriority = Priority(title: "Post-meeting Review", estimatedMinutes: 45, scheduledMinutesFromMidnight: 16 * 60)

        let layout = DayPlanner.computeScheduleLayout(
            day: "2026-10-15",
            calendarEvents: [event],
            priorities: [conflictingPriority, safePriority],
            sessions: [],
            calendar: calendar,
            now: date(15, 8, 0)
        )

        XCTAssertEqual(layout.plannedBlocks.count, 2)
        XCTAssertTrue(layout.plannedBlocks[0].hasConflict)
        XCTAssertEqual(layout.plannedBlocks[0].conflictingEventTitle, "Team Sync")

        XCTAssertFalse(layout.plannedBlocks[1].hasConflict)
        XCTAssertNil(layout.plannedBlocks[1].conflictingEventTitle)
    }
}

@MainActor
final class DayPlanModelTests: XCTestCase {
    private func makeModel(announcer: FakeAnnouncer) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPlan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppModel(store: Store(fileURL: directory.appendingPathComponent("store.json")),
                        engine: EngineHarness().engine, announcer: announcer)
    }

    func testWrapUpPostsTheRecapAndSavesTomorrow() throws {
        let announcer = FakeAnnouncer()
        let model = try makeModel(announcer: announcer)
        model.updateSettings { $0.displayName = "Zixuan" }
        let now = Date()
        let today = [Priority(title: "Lab", isDone: true), Priority(title: "Read")]
        model.isWrappingUpDay = true
        model.wrapUpDay(today: today, tomorrow: [Priority(title: "Quiz prep"), Priority(title: "  ")], now: now)

        XCTAssertEqual(announcer.messages, [
            DiscordMessages.priorityUpdate(name: "Zixuan", title: "Lab", setup: nil),
            DiscordMessages.dayRecap(name: "Zixuan", done: ["Lab"], notDone: ["Read"], tomorrow: ["Quiz prep"],
                                     summary: DaySummary.summarize(day: DayKey.key(for: now), sessions: [],
                                                                   priorities: today)),
        ])
        XCTAssertEqual(model.plan(for: DayKey.key(for: now))?.wrappedUp, true)
        XCTAssertEqual(model.plan(for: DayKey.tomorrow(from: now))?.priorities.map(\.title), ["Quiz prep"])
        XCTAssertEqual(model.todayPlan(now: now).day, DayKey.key(for: now))
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Lab", "Read"])
        XCTAssertTrue(model.todayPlan(now: now).wrappedUp)
        XCTAssertFalse(model.isWrappingUpDay)
        model.startMyDay(now: now)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Lab", "Read"])
        let nextMorning = DayKey.date(for: DayKey.tomorrow(from: now))!
        XCTAssertEqual(model.todayPlan(now: nextMorning).priorities.map(\.title), ["Quiz prep"])
        model.wrapUpDay(today: [Priority(title: "Quiz prep", isDone: true)], tomorrow: [Priority(title: "Exam")], now: now)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Quiz prep"])
        XCTAssertEqual(model.plan(for: DayKey.tomorrow(from: now))?.priorities.map(\.title), ["Exam"])
        let reloaded = Store(fileURL: model.store.fileURL).load().data
        XCTAssertEqual(reloaded.dayPlans.count, 2)
    }

    func testStartMyDayWrapsUpYesterdayBeforeTheNewDay() throws {
        let model = try makeModel(announcer: FakeAnnouncer())
        let now = Date()
        let yesterday = DayKey.previous(DayKey.key(for: now))
        model.updatePlan(day: yesterday) { $0.priorities = [Priority(title: "Lab")] }
        var mornings = 0
        var windows = 0
        model.onShowMorning = { mornings += 1 }
        model.onShowMainWindow = { windows += 1 }

        model.startMyDay(now: now)

        XCTAssertTrue(model.needsPreviousWrapUp(now: now))
        XCTAssertTrue(model.isWrappingUpDay)
        XCTAssertFalse(model.isShowingMorning)
        XCTAssertEqual(mornings, 0)
        XCTAssertEqual(windows, 1)
        XCTAssertEqual(model.todayPlan(now: now).day, yesterday)

        model.wrapUpDay(today: [Priority(title: "Lab", isDone: true)], tomorrow: [Priority(title: "Quiz")], now: now)

        XCTAssertFalse(model.needsPreviousWrapUp(now: now))
        XCTAssertEqual(model.todayPlan(now: now).day, DayKey.key(for: now))
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Quiz"])
        XCTAssertFalse(model.todayPlan(now: now).wrappedUp)
    }

    func testPostDayRecapUsesTheSavedPlans() throws {
        let announcer = FakeAnnouncer()
        let model = try makeModel(announcer: announcer)
        model.updateSettings { $0.displayName = "Zixuan" }
        let now = Date()
        let today = [Priority(title: "Lab", isDone: true), Priority(title: "Read")]
        model.updatePlan(day: DayKey.key(for: now)) { $0.priorities = today }
        model.updatePlan(day: DayKey.tomorrow(from: now)) { $0.priorities = [Priority(title: "Quiz prep")] }

        model.postDayRecap(now: now)

        XCTAssertEqual(announcer.messages, [
            DiscordMessages.dayRecap(name: "Zixuan", done: ["Lab"], notDone: ["Read"], tomorrow: ["Quiz prep"],
                                     summary: DaySummary.summarize(day: DayKey.key(for: now), sessions: [],
                                                                   priorities: today)),
        ])
        XCTAssertEqual(model.plan(for: DayKey.key(for: now))?.wrappedUp, true)
    }

    func testCheckEndOfDayOpensTheWrapUpOncePerDay() throws {
        let model = try makeModel(announcer: FakeAnnouncer())
        model.updateSettings { $0.dayEndMinutes = 0 }   // any time of day is past it
        var shown = 0
        model.onShowMainWindow = { shown += 1 }
        model.checkEndOfDay()
        XCTAssertTrue(model.isWrappingUpDay)
        model.isWrappingUpDay = false
        model.checkEndOfDay()
        XCTAssertFalse(model.isWrappingUpDay)
        XCTAssertEqual(shown, 1)
    }

    func testSetPriorityTicksIt() throws {
        let announcer = FakeAnnouncer()
        let model = try makeModel(announcer: announcer)
        model.updateSettings { $0.displayName = "Zixuan" }
        let subject = Subject(name: "MATH241")
        model.addSubject(subject)
        let day = DayKey.key(for: Date())
        let priority = Priority(title: "Math241 review", subjectID: subject.id)
        model.updatePlan(day: day) { $0.priorities = [priority] }

        model.setPriority(priority.id, done: true, day: day)
        XCTAssertEqual(model.todayPlan().priorities.first?.isDone, true)
        XCTAssertEqual(announcer.messages, [
            DiscordMessages.priorityUpdate(name: "Zixuan", title: "Math241 review", setup: "MATH241"),
        ])

        model.setPriority(priority.id, done: true, day: day)
        model.setPriority(priority.id, done: false, day: day)
        XCTAssertEqual(announcer.messages.count, 1)
        model.setPriority(priority.id, done: true, day: day)
        XCTAssertEqual(announcer.messages.count, 2)
    }

    func testWrapUpAnnouncesOnlyPrioritiesFinishedInThatWrapUp() throws {
        let announcer = FakeAnnouncer()
        let model = try makeModel(announcer: announcer)
        model.updateSettings { $0.displayName = "Zixuan" }
        let now = Date()
        let lab = Priority(title: "Lab", isDone: true)
        let read = Priority(title: "Read")
        model.updatePlan(day: DayKey.key(for: now)) { $0.priorities = [lab, read] }
        var finishedRead = read
        finishedRead.isDone = true
        let today = [lab, finishedRead]

        model.wrapUpDay(today: today, tomorrow: [Priority(title: "Quiz prep")], now: now)

        XCTAssertEqual(announcer.messages, [
            DiscordMessages.priorityUpdate(name: "Zixuan", title: "Read", setup: nil),
            DiscordMessages.dayRecap(name: "Zixuan", done: ["Lab", "Read"], notDone: [], tomorrow: ["Quiz prep"],
                                     summary: DaySummary.summarize(day: DayKey.key(for: now), sessions: [],
                                                                   priorities: today)),
        ])
    }

    // MARK: Time estimates & duration

    func testParseTimeEstimateFromSpokenOrTypedText() {
        let lab = DayPlanner.parseTimeEstimate(from: "Finish CS128 lab 45m")
        XCTAssertEqual(lab.title, "Finish CS128 lab")
        XCTAssertEqual(lab.estimatedMinutes, 45)

        let bio = DayPlanner.parseTimeEstimate(from: "Study biology (1h)")
        XCTAssertEqual(bio.title, "Study biology")
        XCTAssertEqual(bio.estimatedMinutes, 60)

        let paper = DayPlanner.parseTimeEstimate(from: "Read paper (30 min)")
        XCTAssertEqual(paper.title, "Read paper")
        XCTAssertEqual(paper.estimatedMinutes, 30)

        let prep = DayPlanner.parseTimeEstimate(from: "Exam prep 1.5 hours")
        XCTAssertEqual(prep.title, "Exam prep")
        XCTAssertEqual(prep.estimatedMinutes, 90)

        let thesis = DayPlanner.parseTimeEstimate(from: "Write thesis chapters")
        XCTAssertEqual(thesis.title, "Write thesis chapters")
        XCTAssertNil(thesis.estimatedMinutes)
    }

    func testPriorityEstimatedMinutesCodableBackwardsCompatibility() throws {
        // Legacy JSON without estimatedMinutes
        let legacyJSON = """
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"Old task","isDone":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Priority.self, from: legacyJSON)
        XCTAssertEqual(decoded.title, "Old task")
        XCTAssertNil(decoded.estimatedMinutes)

        // New JSON with estimatedMinutes
        let newPriority = Priority(title: "Task with time", estimatedMinutes: 45)
        let encoded = try JSONEncoder().encode(newPriority)
        let roundtrip = try JSONDecoder().decode(Priority.self, from: encoded)
        XCTAssertEqual(roundtrip.title, "Task with time")
        XCTAssertEqual(roundtrip.estimatedMinutes, 45)
    }
}
