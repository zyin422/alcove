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

    func testDayPlanMovePriority() {
        let p1 = Priority(title: "Task 1")
        let p2 = Priority(title: "Task 2")
        let p3 = Priority(title: "Task 3")
        var plan = DayPlan(day: "2026-11-24", priorities: [p1, p2, p3])

        // Move task 3 to top (index 2 -> 0)
        plan.movePriority(from: 2, to: 0)
        XCTAssertEqual(plan.priorities.map(\.title), ["Task 3", "Task 1", "Task 2"])

        // Move task 1 to bottom (index 1 -> 2)
        plan.movePriority(from: 1, to: 2)
        XCTAssertEqual(plan.priorities.map(\.title), ["Task 3", "Task 2", "Task 1"])

        // Invalid indices are no-ops
        plan.movePriority(from: -1, to: 1)
        plan.movePriority(from: 0, to: 99)
        plan.movePriority(from: 1, to: 1)
        XCTAssertEqual(plan.priorities.map(\.title), ["Task 3", "Task 2", "Task 1"])
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

    func testMatchSubjectUsesCourseDepartmentPrefixesDetailsAndSpacedCodes() {
        let research = Subject(name: "Research")
        let ling = Subject(name: "LING100")
        let cs173 = Subject(name: "CS173", details: "CS173 is a Discrete Structure course where I learn introductory proofs.")
        let selfStudy = Subject(name: "Self-study", details: "Self-studying neural networks and deep learning")
        let subjects = [research, ling, cs173, selfStudy]

        XCTAssertEqual(DayPlanner.matchSubject("Research", subjects: subjects), research.id)
        XCTAssertEqual(DayPlanner.matchSubject("Linguistics observations", subjects: subjects), ling.id)
        XCTAssertEqual(DayPlanner.matchSubject("LING 100 worksheet", subjects: subjects), ling.id)
        XCTAssertEqual(DayPlanner.matchSubject("Finish discrete proofs set", subjects: subjects), cs173.id)
        XCTAssertEqual(DayPlanner.matchSubject("Read neural networks paper", subjects: subjects), selfStudy.id)
        XCTAssertNil(DayPlanner.matchSubject("Buy groceries", subjects: subjects))
    }

    func testAutoAssignedSubjectAndFillingUnassignedSetupsRespectOverrides() {
        let research = Subject(name: "Research")
        let ling = Subject(name: "LING100")
        let subjects = [research, ling]

        // Live typing assigns, updates, and clears when unmatched.
        let step1 = DayPlanner.autoAssignedSubject(for: "Research", currentSubjectID: nil, lastAutoMatchedID: nil, userOverrode: false, subjects: subjects)
        XCTAssertEqual(step1.subjectID, research.id)
        let step2 = DayPlanner.autoAssignedSubject(for: "Linguistics observations", currentSubjectID: step1.subjectID, lastAutoMatchedID: step1.autoMatchedID, userOverrode: false, subjects: subjects)
        XCTAssertEqual(step2.subjectID, ling.id)
        let cleared = DayPlanner.autoAssignedSubject(for: "Call mom", currentSubjectID: step2.subjectID, lastAutoMatchedID: step2.autoMatchedID, userOverrode: false, subjects: subjects)
        XCTAssertNil(cleared.subjectID)

        // Manual override (either explicit setup or explicit nil) is preserved while editing title.
        let manual = DayPlanner.autoAssignedSubject(for: "Research", currentSubjectID: nil, lastAutoMatchedID: step1.autoMatchedID, userOverrode: true, subjects: subjects)
        XCTAssertNil(manual.subjectID)

        // Pre-existing setup from AI or prior plan is not wiped when editing to a generic title.
        let preserved = DayPlanner.autoAssignedSubject(for: "Read notes", currentSubjectID: research.id, lastAutoMatchedID: nil, userOverrode: false, subjects: subjects)
        XCTAssertEqual(preserved.subjectID, research.id)

        // Batch fill leaves assigned setups intact and fills unassigned ones.
        let filled = DayPlanner.fillingUnassignedSetups([
            Priority(title: "Research", subjectID: nil),
            Priority(title: "Linguistics observations", subjectID: nil),
            Priority(title: "Custom task", subjectID: research.id),
        ], subjects: subjects)
        XCTAssertEqual(filled.map(\.subjectID), [research.id, ling.id, research.id])
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
        let research = Subject(name: "Research")
        let ling = Subject(name: "LING100")
        let reply = """
        ```json
        {"priorities":[{"title":"Finish lab 3","setup":"cs128"},{"title":"Call mom","setup":""},{"title":"Research","setup":""},{"title":"Linguistics observations","setup":""},{"title":"  ","setup":"x"}]}
        ```
        """
        let parsed = PriorityExtractor.parse(reply, subjects: [cs, research, ling])
        XCTAssertEqual(parsed?.map(\.title), ["Finish lab 3", "Call mom", "Research", "Linguistics observations"])
        XCTAssertEqual(parsed?.map(\.subjectID), [cs.id, nil, research.id, ling.id])
        XCTAssertNil(PriorityExtractor.parse("Sorry, I can't.", subjects: [cs]))

        let prompt = PriorityExtractor.systemPrompt(subjects: [Subject(name: "LING100", details: "Intro to Linguistics")])
        XCTAssertTrue(prompt.contains("LING100: Intro to Linguistics"))
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

    func testActivePriorityFindsFirstIncompletePriorityForSubject() {
        let subA = UUID()
        let subB = UUID()
        let p1 = Priority(title: "Done Task", subjectID: subA, isDone: true)
        let p2 = Priority(title: "Active Task", subjectID: subA, isDone: false)
        let p3 = Priority(title: "Later Task", subjectID: subA, isDone: false)
        let p4 = Priority(title: "Other Subject", subjectID: subB, isDone: false)

        let plan = DayPlan(day: "2026-11-24", priorities: [p1, p2, p3, p4])
        XCTAssertEqual(plan.activePriority(for: subA)?.id, p2.id)
        XCTAssertEqual(plan.activePriority(for: subB)?.id, p4.id)
        XCTAssertNil(plan.activePriority(for: UUID()))
    }

    func testPrepareRolloverFiltersUnfinishedAndResetsCompletionState() {
        let sub = UUID()
        let p1 = Priority(title: "Finished Task", subjectID: sub, isDone: true, estimatedMinutes: 30)
        let p2 = Priority(title: "Unfinished Task 1", subjectID: sub, isDone: false, estimatedMinutes: 45, scheduledMinutesFromMidnight: 600)
        let p3 = Priority(title: "Unfinished Task 2", subjectID: nil, isDone: false, estimatedMinutes: 60)
        let p4 = Priority(title: "Unselected Task", subjectID: sub, isDone: false)

        let selected: Set<UUID> = [p1.id, p2.id, p3.id]
        let rollover = DayPlanner.prepareRollover(from: [p1, p2, p3, p4], selectedIDs: selected)

        XCTAssertEqual(rollover.count, 2)
        XCTAssertEqual(rollover[0].title, "Unfinished Task 1")
        XCTAssertEqual(rollover[0].subjectID, sub)
        XCTAssertEqual(rollover[0].estimatedMinutes, 45)
        XCTAssertFalse(rollover[0].isDone)
        XCTAssertNil(rollover[0].scheduledMinutesFromMidnight, "Rolled-over priorities should reset scheduled time for the new day")

        XCTAssertEqual(rollover[1].title, "Unfinished Task 2")
        XCTAssertEqual(rollover[1].estimatedMinutes, 60)
        XCTAssertFalse(rollover[1].isDone)
    }

    func testAppendNewMergesRolloverWithoutDuplication() {
        let sub = UUID()
        let existing = [Priority(title: "Existing Task", subjectID: sub)]
        let rollover = [
            Priority(title: "Existing task", subjectID: sub, estimatedMinutes: 45),
            Priority(title: "New Task", subjectID: sub, estimatedMinutes: 30)
        ]

        let merged = DayPlanner.appendNew(rollover, to: existing)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].title, "Existing Task")
        XCTAssertEqual(merged[0].estimatedMinutes, 45, "Should enrich missing metadata")
        XCTAssertEqual(merged[1].title, "New Task")
        XCTAssertEqual(merged[1].estimatedMinutes, 30)
    }

    func testActivePriorityPrefersAnchorOverEarlierPriorities() {
        let sub = UUID()
        let p1 = Priority(title: "Task 1", subjectID: sub, isDone: false, isAnchor: false)
        let p2 = Priority(title: "Task 2 (Anchor)", subjectID: sub, isDone: false, isAnchor: true)
        let p3 = Priority(title: "Task 3", subjectID: sub, isDone: false, isAnchor: false)

        let plan = DayPlan(day: "2026-11-24", priorities: [p1, p2, p3])
        XCTAssertEqual(plan.activePriority(for: sub)?.id, p2.id, "Should prioritize starred anchor priority")
    }

    func testPriorityAnchorCodableBackwardsCompatibility() throws {
        let legacyJSON = """
        {"id":"A621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"Old task","isDone":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Priority.self, from: legacyJSON)
        XCTAssertEqual(decoded.title, "Old task")
        XCTAssertFalse(decoded.isAnchor)

        let anchor = Priority(title: "Starred task", isAnchor: true)
        let encoded = try JSONEncoder().encode(anchor)
        let roundtrip = try JSONDecoder().decode(Priority.self, from: encoded)
        XCTAssertEqual(roundtrip.title, "Starred task")
        XCTAssertTrue(roundtrip.isAnchor)
    }

    func testAvailableFocusWindowsComputesGapsBetweenCalendarEvents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_760_000_000) // pick deterministic components
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        let d0 = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 9, minute: 0))!
        let m1Start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 10, minute: 0))!
        let m1End = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 11, minute: 0))!
        let m2Start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 11, minute: 15))!
        let m2End = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12, minute: 0))!

        let iso = ISO8601DateFormatter()
        let events = [
            GoogleEvent(id: "1", summary: "Standup",
                        start: GoogleEventTime(dateTime: iso.string(from: m1Start), date: nil),
                        end: GoogleEventTime(dateTime: iso.string(from: m1End), date: nil)),
            GoogleEvent(id: "2", summary: "Review",
                        start: GoogleEventTime(dateTime: iso.string(from: m2Start), date: nil),
                        end: GoogleEventTime(dateTime: iso.string(from: m2End), date: nil))
        ]

        let windows = DayPlanner.availableFocusWindows(
            calendarEvents: events,
            dayStartMinutes: 7 * 60,
            dayEndMinutes: 15 * 60,
            minimumMinutes: 25,
            now: d0,
            isToday: true,
            calendar: calendar
        )

        // 9:00-10:00 (60m) and 12:00-15:00 (180m); the 15m gap between 11:00 and 11:15 is filtered (<25m).
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].startMinutes, 9 * 60)
        XCTAssertEqual(windows[0].endMinutes, 10 * 60)
        XCTAssertEqual(windows[0].suggestedBlockMinutes, 50)
        XCTAssertEqual(windows[1].startMinutes, 12 * 60)
        XCTAssertEqual(windows[1].endMinutes, 15 * 60)
        XCTAssertEqual(windows[1].suggestedBlockMinutes, 90)
    }

    func testBuildTomorrowReviewListPreservesBothRolloverAndHashtagParkedThoughts() {
        let research = Subject(name: "Research", sites: ["arxiv.org"])
        let existing = Priority(title: "Read paper", subjectID: research.id, isDone: false, estimatedMinutes: 40)
        let result = DayPlanner.buildTomorrowReviewList(
            base: [Priority(title: "Morning warmup")],
            rolloverSource: [existing],
            selectedRolloverIDs: [existing.id],
            parkedThoughts: ["#research Write ablation notes 30m"],
            subjects: [research]
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains { $0.title == "Morning warmup" })
        XCTAssertTrue(result.contains { $0.title == "Read paper" && $0.subjectID == research.id && $0.estimatedMinutes == 40 })
        XCTAssertTrue(result.contains { $0.title == "Write ablation notes" && $0.subjectID == research.id && $0.estimatedMinutes == 30 })
    }

    func testNormalizingReviewPrioritiesExtractsInlineDurationAndAssignsSubject() {
        let research = Subject(name: "Research", details: "ML ablations", sites: ["arxiv.org"])
        let draft = Priority(title: "Write research ablation 60m", isAnchor: true)
        let normalized = DayPlanner.normalizingReviewPriorities([draft], subjects: [research])

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].title, "Write research ablation")
        XCTAssertEqual(normalized[0].estimatedMinutes, 60)
        XCTAssertEqual(normalized[0].subjectID, research.id)
        XCTAssertTrue(normalized[0].isAnchor)
    }

    func testWrapUpTelemetrySummarizesFocusedWorkAndPriorities() {
        let cs = Subject(name: "CS128", colorHex: "#4f46e5")
        let math = Subject(name: "MATH241", colorHex: "#059669")
        let day = "2026-10-10"
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10, minute: 0))!
        let sessions = [
            Session(subjectID: cs.id, subjectName: "CS128", mode: .open, start: now, end: now.addingTimeInterval(3600), outcome: .completed),
            Session(subjectID: math.id, subjectName: "MATH241", mode: .open, start: now.addingTimeInterval(4000), end: now.addingTimeInterval(5800), outcome: .completed),
            Session(subjectID: cs.id, subjectName: "CS128", mode: .open, start: now, end: now.addingTimeInterval(900), outcome: .bailed),
        ]
        let priorities = [
            Priority(title: "Lab 1", isDone: true),
            Priority(title: "Lab 2", isDone: false),
        ]

        let telemetry = DayPlanner.wrapUpTelemetry(
            for: day,
            sessions: sessions,
            priorities: priorities,
            subjects: [cs, math],
            dailyTargetMinutes: 90
        )

        XCTAssertEqual(telemetry.focusedSeconds, 5400, accuracy: 0.1)
        XCTAssertEqual(telemetry.completedSessions, 2)
        XCTAssertEqual(telemetry.prioritiesDone, 1)
        XCTAssertEqual(telemetry.prioritiesTotal, 2)
        XCTAssertTrue(telemetry.isTargetMet)
        XCTAssertEqual(telemetry.subjects.map(\.name), ["CS128", "MATH241"])
    }

    @MainActor func testSortPrioritiesAnchorsFirstAndDeferAllOpenPriorities() throws {
        let model = try makeModel(announcer: FakeAnnouncer())
        let day = DayKey.key(for: Date())
        let next = DayKey.next(day)

        model.updatePlan(day: day) { plan in
            plan.priorities = [
                Priority(title: "Done 1", isDone: true, isAnchor: true),
                Priority(title: "Open Regular", isDone: false, isAnchor: false),
                Priority(title: "Open Anchor", isDone: false, isAnchor: true),
            ]
        }

        model.sortPrioritiesAnchorsFirst(day: day)
        XCTAssertEqual(model.plan(for: day)?.priorities.map(\.title), ["Open Anchor", "Open Regular", "Done 1"])

        let deferred = model.deferAllOpenPrioritiesToTomorrow(from: day)
        XCTAssertEqual(deferred, 2)
        XCTAssertEqual(model.plan(for: day)?.priorities.map(\.title), ["Done 1"])
        XCTAssertEqual(model.plan(for: next)?.priorities.map(\.title), ["Open Anchor", "Open Regular"])
    }

    func testNextCalendarAlertReportsOngoingAndUpcomingWithinTwoHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let iso = ISO8601DateFormatter()

        let upcomingEvent = GoogleEvent(
            id: "u1",
            summary: "Lab Sync",
            start: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(22 * 60)), date: nil),
            end: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(52 * 60)), date: nil)
        )
        let upcomingAlert = DayPlanner.nextCalendarAlert(in: [upcomingEvent], at: now)
        XCTAssertEqual(upcomingAlert, CalendarEventAlert(title: "Lab Sync", minutes: 22, isOngoing: false))

        let ongoingEvent = GoogleEvent(
            id: "o1",
            summary: "Lecture",
            start: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(-10 * 60)), date: nil),
            end: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(15 * 60)), date: nil)
        )
        let ongoingAlert = DayPlanner.nextCalendarAlert(in: [ongoingEvent, upcomingEvent], at: now)
        XCTAssertEqual(ongoingAlert, CalendarEventAlert(title: "Lecture", minutes: 15, isOngoing: true))
    }

    func testDidCrossDailyGoalFiresOnceWhenCrossingThreshold() {
        let subID = UUID()
        let cal = Calendar.current
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9, minute: 0))!
        let prior = Session(subjectID: subID, subjectName: "CS128", mode: .goal(minutes: 90),
                            start: morning, end: morning.addingTimeInterval(5400), outcome: .completed)
        let finisher = Session(subjectID: subID, subjectName: "CS128", mode: .goal(minutes: 30),
                               start: morning.addingTimeInterval(6000), end: morning.addingTimeInterval(7800), outcome: .completed)

        XCTAssertTrue(DayPlanner.didCrossDailyGoal(previousSessions: [prior], completedSession: finisher, dailyTargetMinutes: 120))
        XCTAssertFalse(DayPlanner.didCrossDailyGoal(previousSessions: [prior, finisher],
                                                    completedSession: Session(subjectID: subID, subjectName: "CS128", mode: .goal(minutes: 30),
                                                                            start: morning.addingTimeInterval(8000), end: morning.addingTimeInterval(9800), outcome: .completed),
                                                    dailyTargetMinutes: 120))
    }

    func testMeetingFitRecommendationFitsBeforeUpcomingEventAndIgnoresOngoing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let iso = ISO8601DateFormatter()

        let upcoming = GoogleEvent(
            id: "1",
            summary: "Team Standup",
            start: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(35 * 60)), date: nil),
            end: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(65 * 60)), date: nil)
        )
        let rec = DayPlanner.meetingFitRecommendation(in: [upcoming], at: now)
        XCTAssertEqual(rec, MeetingFitRecommendation(meetingTitle: "Team Standup", minutesUntil: 35, fitMinutes: 30))

        let ongoing = GoogleEvent(
            id: "2",
            summary: "Now",
            start: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(-10 * 60)), date: nil),
            end: GoogleEventTime(dateTime: iso.string(from: now.addingTimeInterval(20 * 60)), date: nil)
        )
        XCTAssertNil(DayPlanner.meetingFitRecommendation(in: [ongoing, upcoming], at: now))
    }

    func testScheduleConflictTitleDetectsOverlappingCalendarEvent() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15, minute: 0))!
        let iso = ISO8601DateFormatter()
        let event = GoogleEvent(
            id: "evt",
            summary: "Systems Sync",
            start: GoogleEventTime(dateTime: iso.string(from: start), date: nil),
            end: GoogleEventTime(dateTime: iso.string(from: end), date: nil)
        )

        let overlapping = Priority(title: "Study", estimatedMinutes: 45, scheduledMinutesFromMidnight: 13 * 60 + 30)
        XCTAssertEqual(DayPlanner.scheduleConflictTitle(for: overlapping, in: [event]), "Systems Sync")

        let clear = Priority(title: "Study", estimatedMinutes: 45, scheduledMinutesFromMidnight: 15 * 60)
        XCTAssertNil(DayPlanner.scheduleConflictTitle(for: clear, in: [event]))
    }

    func testWorkloadCapacityFitComputesClearTimeMarginAndOverage() {
        let fits = DayPlanner.workloadCapacityFit(openEstimatedMinutes: 90, clearMinutes: 150)
        XCTAssertEqual(fits?.fits, true)
        XCTAssertEqual(fits?.overageMinutes, 0)

        let tight = DayPlanner.workloadCapacityFit(openEstimatedMinutes: 185, clearMinutes: 150)
        XCTAssertEqual(tight?.fits, false)
        XCTAssertEqual(tight?.overageMinutes, 35)

        XCTAssertNil(DayPlanner.workloadCapacityFit(openEstimatedMinutes: 0, clearMinutes: 150))
    }
}
