import XCTest
@testable import Tofu

/// Scripted GoogleAPI: records every call, serves canned data, can fail on command.
@MainActor final class FakeGoogleAPI: GoogleAPI {
    var tasks: [GoogleTask] = []
    var calendars: [GoogleCalendarInfo] = []
    var events: [String: [GoogleEvent]] = [:]      // calendarID -> events
    var error: Error?
    var insertEventErrors: [String: Error] = [:]   // calendarID -> error for insertEvent
    var listEventsErrors: [String: Error] = [:]    // calendarID -> error for listEvents
    var inboxIDs: [String] = []
    var inboxMessages: [String: InboxMessage] = [:]   // message id -> message
    var gmailError: Error?                          // thrown by listMessageIDs
    var log: [String] = []
    private var nextID = 100

    func listTasks() async throws -> [GoogleTask] { try bump("listTasks"); return tasks }
    func insertTask(title: String, due: String?) async throws -> GoogleTask {
        try bump("insertTask \(title)")
        nextID += 1
        let task = GoogleTask(id: "t\(nextID)", title: title, status: "needsAction", completed: nil, due: due)
        tasks.append(task)
        return task
    }
    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask {
        try bump("patchTask \(id) \(title ?? "-") \(status ?? "-")")
        return GoogleTask(id: id, title: title, status: status ?? "needsAction", completed: nil, due: nil)
    }
    func deleteTask(id: String) async throws { try bump("deleteTask \(id)") }
    func listCalendars() async throws -> [GoogleCalendarInfo] { try bump("listCalendars"); return calendars }
    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo {
        try bump("insertCalendar \(summary)")
        return GoogleCalendarInfo(id: "tofu-cal", summary: summary, selected: nil)
    }
    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws {
        try bump("insertEvent \(calendarID) \(summary)")
        if let failure = insertEventErrors[calendarID] { throw failure }
    }
    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        try bump("listEvents \(calendarID)")
        if let failure = listEventsErrors[calendarID] { throw failure }
        return events[calendarID] ?? []
    }
    func listMessageIDs(query: String, maxResults: Int) async throws -> [String] {
        try bump("listMessageIDs \(query) \(maxResults)")
        if let gmailError { throw gmailError }
        return inboxIDs
    }
    func message(id: String) async throws -> InboxMessage {
        try bump("message \(id)")
        guard let message = inboxMessages[id] else { throw GoogleError.http(404) }
        return message
    }
    private func bump(_ entry: String) throws { log.append(entry); if let error { throw error } }
}

@MainActor final class GoogleSyncTests: XCTestCase {
    private var api = FakeGoogleAPI()
    private var settings = AppSettings()
    private var plan = DayPlan(day: DayKey.key(for: Date()))
    private var savedCalendarID: String??
    private var errors: [String] = []
    /// What the token's scopes cover, as AppModel answers it from the stored grant.
    private var granted: Set<GoogleService> = Set(GoogleService.allCases)

    private func makeSync(connected: Bool = true) -> GoogleSync {
        GoogleSync(api: api,
                   settings: { self.settings },
                   isConnected: { connected },
                   plan: { self.plan },
                   applyPlan: { self.plan = $0 },
                   saveCalendarID: { self.savedCalendarID = $0; self.settings.googleCalendarID = $0 },
                   onError: { self.errors.append($0) },
                   canUse: { self.granted.contains($0) })
    }

    /// Settings with only Gmail on.
    private func gmailOnly() {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        settings.googleGmailEnabled = true
    }

    private func mail(_ id: String, subject: String = "Hi") -> InboxMessage {
        InboxMessage(id: id, from: "Jane <jane@x.edu>", subject: subject, snippet: "", date: nil)
    }

    func testInboxPullsUnreadPrimaryMail() async {
        gmailOnly()
        api.inboxIDs = ["m1", "m2"]
        api.inboxMessages = ["m1": mail("m1", subject: "PS4 due Friday"), "m2": mail("m2")]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertEqual(sync.inbox.map(\.subject), ["PS4 due Friday", "Hi"])
        XCTAssertEqual(api.log.first, "listMessageIDs is:unread category:primary newer_than:3d 10")
    }

    func testInboxFetchesOnlyNewMessages() async {
        gmailOnly()
        api.inboxIDs = ["m1"]
        api.inboxMessages = ["m1": mail("m1"), "m2": mail("m2")]
        let sync = makeSync()
        await sync.syncNow()
        api.log.removeAll()
        api.inboxIDs = ["m2", "m1"]
        await sync.syncNow()
        XCTAssertEqual(api.log.filter { $0.hasPrefix("message ") }, ["message m2"], "m1 is already held")
        XCTAssertEqual(sync.inbox.map(\.id), ["m2", "m1"])
    }

    func testInboxSkipsAMessageDeletedMidPull() async {
        gmailOnly()
        api.inboxIDs = ["gone", "m1"]
        api.inboxMessages = ["m1": mail("m1")]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertEqual(sync.inbox.map(\.id), ["m1"])
        XCTAssertTrue(errors.isEmpty)
    }

    func testGmailRefusedHidesInboxQuietly() async {
        gmailOnly()
        api.inboxIDs = ["m1"]
        api.inboxMessages = ["m1": mail("m1")]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertFalse(sync.inbox.isEmpty)
        api.gmailError = GoogleError.http(403)
        await sync.syncNow()
        XCTAssertTrue(sync.inbox.isEmpty)
        XCTAssertTrue(sync.isGmailRefused)
        XCTAssertTrue(errors.isEmpty, "a disabled Gmail API is shown on Connections, not toasted: \(errors)")
        api.gmailError = nil
        await sync.syncNow()
        XCTAssertFalse(sync.isGmailRefused)
    }

    func testGmailNotGrantedIsSkipped() async {
        gmailOnly()
        granted.remove(.gmail)
        await makeSync().syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("listMessageIDs") }, "\(api.log)")
        XCTAssertTrue(errors.isEmpty)
    }

    func testTurningGmailOffClearsTheInbox() async {
        gmailOnly()
        api.inboxIDs = ["m1"]
        api.inboxMessages = ["m1": mail("m1")]
        let sync = makeSync()
        await sync.syncNow()
        settings.googleGmailEnabled = false
        await sync.syncNow()
        XCTAssertTrue(sync.inbox.isEmpty)
    }

    func testTasksNotGrantedAreSkipped() async {
        gmailOnly()
        settings.googleTasksSyncEnabled = true
        granted.remove(.tasks)
        await makeSync().syncNow()
        XCTAssertFalse(api.log.contains("listTasks"), "\(api.log)")
    }

    func testStopClearsInbox() async {
        gmailOnly()
        api.inboxIDs = ["m1"]
        api.inboxMessages = ["m1": mail("m1")]
        let sync = makeSync()
        await sync.syncNow()
        sync.stop()
        XCTAssertTrue(sync.inbox.isEmpty)
    }

    func testSyncPullsTasksIntoPlan() async {
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        await makeSync().syncNow()
        XCTAssertEqual(plan.priorities.map(\.title), ["Read"])
        XCTAssertEqual(plan.priorities.map(\.googleTaskID), ["t1"])
    }

    func testSyncInsertsUnlinkedPrioritiesAndLinksThem() async {
        plan.priorities = [Priority(title: "Added locally")]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        await makeSync().syncNow()
        XCTAssertTrue(api.log.contains { $0.hasPrefix("insertTask Added locally") })
        XCTAssertNotNil(plan.priorities.first?.googleTaskID, "the returned id must be linked back")
    }

    func testApplyingRemotePlanPushesNothing() async {
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        // applyPlan in AppModel routes through updatePlan, which reports back to planChanged. Simulate that:
        let old = plan
        await sync.syncNow()
        sync.planChanged(from: old, to: plan)   // must be ignored while/after a remote apply of the same content
        await Task.yield()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertTask") }, "remote apply must not echo back: \(api.log)")
    }

    func testReentrantPlanChangedDuringApplyPushesNothing() async {
        var local = Priority(title: "Read"); local.googleTaskID = "t1"
        plan.priorities = [local]
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "completed", completed: GoogleEventTime.rfc3339.string(from: Date()), due: nil)]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        var holder: GoogleSync?
        let sync = GoogleSync(api: api, settings: { self.settings }, isConnected: { true }, plan: { self.plan },
                              applyPlan: { new in
                                  let old = self.plan
                                  self.plan = new
                                  holder?.planChanged(from: old, to: new)   // AppModel's updatePlan echo
                              },
                              saveCalendarID: { _ in })
        holder = sync
        await sync.syncNow()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(plan.priorities.first?.isDone == true)
        XCTAssertFalse(api.log.contains { $0.hasPrefix("patchTask") || $0.hasPrefix("insertTask") || $0.hasPrefix("deleteTask") }, "\(api.log)")
    }

    func testSyncDuringPushDoesNotDoubleInsert() async {
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        let old = plan
        plan.priorities = [Priority(title: "New")]
        let sync = makeSync()
        sync.planChanged(from: old, to: plan)   // schedules a push
        await sync.syncNow()                    // inserts and links first
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(api.log.filter { $0.hasPrefix("insertTask") }.count, 1, "\(api.log)")
    }

    func testPlanChangedPushesDiff() async {
        var linked = Priority(title: "A"); linked.googleTaskID = "tA"
        let old = DayPlan(day: plan.day, priorities: [linked])
        var newDone = linked; newDone.isDone = true
        let new = DayPlan(day: plan.day, priorities: [newDone])
        let sync = makeSync()
        sync.planChanged(from: old, to: new)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(api.log, ["patchTask tA - completed"])
    }

    func testPlanChangedWhenTasksSyncOffDoesNothing() async {
        settings.googleTasksSyncEnabled = false
        let old = DayPlan(day: plan.day, priorities: [])
        let new = DayPlan(day: plan.day, priorities: [Priority(title: "X")])
        makeSync().planChanged(from: old, to: new)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(api.log.isEmpty)
    }

    func testSessionEndedQueuesAndSyncPushesEvent() async {
        api.calendars = []
        settings.googleTasksSyncEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        let start = Date().addingTimeInterval(-1800)
        var session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 30), start: start)
        session.end = Date(); session.outcome = .completed
        sync.sessionEnded(session)
        await sync.syncNow()
        XCTAssertTrue(api.log.contains("insertCalendar Tofu"), "no Tofu calendar yet, create it: \(api.log)")
        XCTAssertTrue(api.log.contains("insertEvent tofu-cal Focus: CS128"))
        XCTAssertEqual(savedCalendarID, "tofu-cal")
        api.log.removeAll()
        await sync.syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertEvent") }, "pushed once, not again")
    }

    func testDeletedCachedCalendarIsRecreatedAndRetriedOnce() async {
        settings.googleTasksSyncEnabled = false
        settings.googleShowEventsEnabled = false
        settings.googleCalendarID = "dead-cal"
        api.calendars = []
        api.insertEventErrors = ["dead-cal": GoogleError.http(404)]
        var saved: [String?] = []
        let sync = GoogleSync(api: api, settings: { self.settings }, isConnected: { true }, plan: { self.plan },
                              applyPlan: { self.plan = $0 },
                              saveCalendarID: { saved.append($0); self.settings.googleCalendarID = $0 },
                              onError: { self.errors.append($0) })
        var session = Session(subjectID: UUID(), subjectName: "X", mode: .open, start: Date().addingTimeInterval(-600))
        session.end = Date(); session.outcome = .completed
        sync.sessionEnded(session)
        await sync.syncNow()
        XCTAssertEqual(api.log.filter { $0 == "insertEvent dead-cal Focus: X" }.count, 1, "\(api.log)")
        XCTAssertEqual(api.log.filter { $0 == "insertEvent tofu-cal Focus: X" }.count, 1, "\(api.log)")
        XCTAssertEqual(saved, [nil, "tofu-cal"])
        XCTAssertTrue(errors.isEmpty)
        api.log.removeAll()
        await sync.syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertEvent") }, "queue drained")
    }

    func testExistingTofuCalendarIsReusedNotRecreated() async {
        api.calendars = [GoogleCalendarInfo(id: "cal-old", summary: "Tofu", selected: nil)]
        settings.googleTasksSyncEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        var session = Session(subjectID: UUID(), subjectName: "X", mode: .open, start: Date().addingTimeInterval(-600))
        session.end = Date(); session.outcome = .completed
        sync.sessionEnded(session)
        await sync.syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertCalendar") })
        XCTAssertTrue(api.log.contains("insertEvent cal-old Focus: X"))
    }

    func testEventsPulledFromSelectedCalendarsExcludingTofu() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        settings.googleCalendarID = "tofu-cal"
        api.calendars = [GoogleCalendarInfo(id: "primary", summary: "Me", selected: true),
                         GoogleCalendarInfo(id: "tofu-cal", summary: "Tofu", selected: true),
                         GoogleCalendarInfo(id: "ignored", summary: "Off", selected: false)]
        api.events = ["primary": [GoogleEvent(id: "e1", summary: "Lecture",
                                              start: GoogleEventTime(dateTime: "2026-10-15T09:00:00-05:00", date: nil),
                                              end: GoogleEventTime(dateTime: "2026-10-15T09:50:00-05:00", date: nil))]]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertEqual(sync.todayEvents.map(\.id), ["e1"])
        XCTAssertTrue(api.log.contains("listEvents primary"))
        XCTAssertFalse(api.log.contains("listEvents tofu-cal"))
        XCTAssertFalse(api.log.contains("listEvents ignored"))
    }

    func testOneFailingCalendarDoesNotHideTheOthers() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        api.calendars = [GoogleCalendarInfo(id: "shared", summary: "Shared", selected: true),
                         GoogleCalendarInfo(id: "primary", summary: "Me", selected: true)]
        api.listEventsErrors = ["shared": GoogleError.http(403)]
        api.events = ["primary": [GoogleEvent(id: "e1", summary: "Lecture",
                                              start: GoogleEventTime(dateTime: "2026-10-15T09:00:00-05:00", date: nil),
                                              end: GoogleEventTime(dateTime: "2026-10-15T09:50:00-05:00", date: nil))]]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertEqual(sync.todayEvents.map(\.id), ["e1"])
        XCTAssertTrue(errors.isEmpty, "a partial failure is not a failed cycle: \(errors)")
    }

    func testAllCalendarsFailingReportsError() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        api.calendars = [GoogleCalendarInfo(id: "shared", summary: "Shared", selected: true)]
        api.listEventsErrors = ["shared": GoogleError.http(404)]
        await makeSync().syncNow()
        XCTAssertEqual(errors.count, 1)
    }

    func testUncachedTofuCalendarIsExcludedByName() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        api.calendars = [GoogleCalendarInfo(id: "tofu-other", summary: "Tofu", selected: true)]
        await makeSync().syncNow()
        XCTAssertFalse(api.log.contains("listEvents tofu-other"), "\(api.log)")
    }

    func testStopClearsPulledEvents() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        api.calendars = [GoogleCalendarInfo(id: "primary", summary: "Me", selected: true)]
        api.events = ["primary": [GoogleEvent(id: "e1", summary: "Lecture",
                                              start: GoogleEventTime(dateTime: "2026-10-15T09:00:00-05:00", date: nil),
                                              end: GoogleEventTime(dateTime: "2026-10-15T09:50:00-05:00", date: nil))]]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertFalse(sync.todayEvents.isEmpty)
        sync.stop()
        XCTAssertTrue(sync.todayEvents.isEmpty)
    }

    func testUnchangedPullWritesNoPlan() async {
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        var applies = 0
        let sync = GoogleSync(api: api, settings: { self.settings }, isConnected: { true }, plan: { self.plan },
                              applyPlan: { applies += 1; self.plan = $0 }, saveCalendarID: { _ in })
        await sync.syncNow()
        XCTAssertEqual(applies, 0, "an empty Google list must not create today's plan")
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)]
        await sync.syncNow()
        await sync.syncNow()
        XCTAssertEqual(applies, 1, "the second, identical pull writes nothing")
    }

    func testInsertedTaskIsDueOnTheLocalDay() async {
        plan.priorities = [Priority(title: "Added locally")]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        await makeSync().syncNow()
        XCTAssertEqual(api.tasks.last?.due, DayKey.key(for: Date()) + "T00:00:00.000Z")
    }

    func testStatusPushSendsOnlyDoneFlips() async {
        var linked = Priority(title: "A"); linked.googleTaskID = "tA"
        var gone = Priority(title: "B"); gone.googleTaskID = "tB"
        let old = DayPlan(day: "2026-10-14", priorities: [linked, gone])
        var done = linked; done.isDone = true; done.title = "A renamed"
        let new = DayPlan(day: "2026-10-14", priorities: [done, Priority(title: "New")])
        makeSync().pushStatusChanges(from: old, to: new)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(api.log, ["patchTask tA - completed"])
    }

    func testSyncWhenDisconnectedDoesNothing() async {
        api.tasks = [GoogleTask(id: "t1", title: "X", status: "needsAction", completed: nil, due: nil)]
        await makeSync(connected: false).syncNow()
        XCTAssertTrue(api.log.isEmpty)
    }

    func testSyncAfterRevocationIsQuietNoop() async {
        api.error = GoogleAuthError.revoked
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertTrue(errors.isEmpty, "revocation flips the UI to Connect; no toast storm")
    }

    func testTransientErrorReportsOnceNotEveryCycle() async {
        api.error = GoogleError.http(500)
        let sync = makeSync()
        await sync.syncNow()
        await sync.syncNow()
        XCTAssertEqual(errors.count, 1, "only the transition into failure is reported")
        api.error = nil
        await sync.syncNow()
        api.error = GoogleError.http(500)
        await sync.syncNow()
        XCTAssertEqual(errors.count, 2, "a new failure after a success is reported again")
    }

    // MARK: shouldLog / event text

    func testShouldLogRules() {
        let start = Date().addingTimeInterval(-3600)
        var completed = Session(subjectID: UUID(), subjectName: "A", mode: .open, start: start)
        completed.end = start.addingTimeInterval(60); completed.outcome = .completed
        XCTAssertTrue(GoogleSync.shouldLog(completed))
        var shortBail = completed; shortBail.outcome = .bailed; shortBail.end = start.addingTimeInterval(200)
        XCTAssertFalse(GoogleSync.shouldLog(shortBail), "bailed under 5 minutes")
        var longBail = completed; longBail.outcome = .bailed; longBail.end = start.addingTimeInterval(400)
        XCTAssertTrue(GoogleSync.shouldLog(longBail))
        var demo = completed; demo.isDemo = true
        XCTAssertFalse(GoogleSync.shouldLog(demo))
        var interrupted = completed; interrupted.outcome = .interrupted
        XCTAssertFalse(GoogleSync.shouldLog(interrupted))
        var unfinished = completed; unfinished.end = nil; unfinished.outcome = nil
        XCTAssertFalse(GoogleSync.shouldLog(unfinished))
    }

    func testEventTexts() {
        let start = Date().addingTimeInterval(-3000)
        var session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 50), start: start,
                              blockedAttempts: 3, closedTabs: 2)
        session.end = start.addingTimeInterval(3000); session.outcome = .completed
        XCTAssertEqual(GoogleSync.eventSummary(for: session), "Focus: CS128")
        let description = GoogleSync.eventDescription(for: session)
        XCTAssertTrue(description.contains("50 min goal"))
        XCTAssertTrue(description.contains("completed"))
        XCTAssertTrue(description.contains("3 blocked"))
        XCTAssertTrue(description.contains("2 tabs closed"))
    }
}
