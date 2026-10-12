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

    func testWorkingDayMovesToTomorrowAfterWrapUp() {
        let now = date(11, 6, 17)
        XCTAssertEqual(DayPlanner.workingDay(now: now, plans: [], calendar: calendar), "2026-10-11")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [DayPlan(day: "2026-10-11", wrappedUp: false)], calendar: calendar),
            "2026-10-11")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [DayPlan(day: "2026-10-11", wrappedUp: true)], calendar: calendar),
            "2026-10-12")
        XCTAssertEqual(
            DayPlanner.workingDay(now: now, plans: [
                DayPlan(day: "2026-10-11", wrappedUp: true),
                DayPlan(day: "2026-10-12", wrappedUp: true),
            ], calendar: calendar),
            "2026-10-13")
        XCTAssertEqual(DayKey.next("2026-10-11"), "2026-10-12")
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
            DiscordMessages.dayRecap(name: "Zixuan", done: ["Lab"], notDone: ["Read"], tomorrow: ["Quiz prep"],
                                     summary: DaySummary.summarize(day: DayKey.key(for: now), sessions: [],
                                                                   priorities: today)),
        ])
        XCTAssertEqual(model.plan(for: DayKey.key(for: now))?.wrappedUp, true)
        XCTAssertEqual(model.plan(for: DayKey.tomorrow(from: now))?.priorities.map(\.title), ["Quiz prep"])
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Quiz prep"])
        XCTAssertFalse(model.todayPlan(now: now).wrappedUp)
        XCTAssertFalse(model.isWrappingUpDay)
        model.startMyDay(now: now)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Quiz prep"])
        model.wrapUpDay(today: [Priority(title: "Quiz prep", isDone: true)], tomorrow: [Priority(title: "Exam")], now: now)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Exam"])
        let reloaded = Store(fileURL: model.store.fileURL).load().data
        XCTAssertEqual(reloaded.dayPlans.count, 3)
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
        let model = try makeModel(announcer: FakeAnnouncer())
        let day = DayKey.key(for: Date())
        let priority = Priority(title: "Lab")
        model.updatePlan(day: day) { $0.priorities = [priority] }
        model.setPriority(priority.id, done: true, day: day)
        XCTAssertEqual(model.todayPlan().priorities.first?.isDone, true)
    }
}
