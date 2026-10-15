import XCTest
@testable import Tofu

/// Scripted GoogleAPI: records every call, serves canned data, can fail on command.
@MainActor final class FakeGoogleAPI: GoogleAPI {
    var tasks: [GoogleTask] = []
    var calendars: [GoogleCalendarInfo] = []
    var events: [String: [GoogleEvent]] = [:]      // calendarID -> events
    var error: Error?
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
    }
    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        try bump("listEvents \(calendarID)")
        return events[calendarID] ?? []
    }
    private func bump(_ entry: String) throws { log.append(entry); if let error { throw error } }
}

@MainActor final class GoogleSyncTests: XCTestCase {
    private var api = FakeGoogleAPI()
    private var settings = AppSettings()
    private var plan = DayPlan(day: DayKey.key(for: Date()))
    private var savedCalendarID: String??
    private var errors: [String] = []

    private func makeSync(connected: Bool = true) -> GoogleSync {
        GoogleSync(api: api,
                   settings: { self.settings },
                   isConnected: { connected },
                   plan: { self.plan },
                   applyPlan: { self.plan = $0 },
                   saveCalendarID: { self.savedCalendarID = $0; self.settings.googleCalendarID = $0 },
                   onError: { self.errors.append($0) })
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
