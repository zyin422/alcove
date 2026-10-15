import XCTest
@testable import Tofu

@MainActor final class GoogleWiringTests: XCTestCase {
    /// Stands in for the Keychain slot that holds the refresh token.
    private final class TokenBox { var value: String? = "rt-1" }

    private let api = FakeGoogleAPI()
    private let tokenBox = TokenBox()
    private var todayKey: String { DayKey.key(for: Date()) }

    /// A model over a temp store and a connected fake Google; the calendar-pull toggle is off so only tasks
    /// and session logging reach the fake.
    private func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleWiringTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = Store(fileURL: directory.appendingPathComponent("store.json"))
        let box = tokenBox
        let auth = GoogleAuth(readToken: { box.value }, writeToken: { box.value = $0 })
        let model = AppModel(store: store, engine: EngineHarness().engine, googleAuth: auth, googleAPI: api)
        // Before the first suspension, so the sync started by init reads the new setting.
        model.updateSettings { $0.googleShowEventsEnabled = false }
        addTeardownBlock { @MainActor in model.googleSync?.stop() }
        return model
    }

    /// Polls the fake's log (up to 2 s) until `condition` holds; returns whether it did.
    @discardableResult
    private func waitForLog(_ condition: ([String]) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition(api.log) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition(api.log)
    }

    /// Lets the sync that init started finish its first cycle.
    private func waitForInitialSync() async {
        await waitForLog { $0.contains("listTasks") }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testTogglingPriorityPushesPatch() async throws {
        api.tasks = [GoogleTask(id: "tA", title: "A", status: "needsAction", completed: nil, due: nil)]
        let model = try makeModel()
        let linked = Priority(title: "A", googleTaskID: "tA")
        model.updatePlan(day: todayKey) { $0.priorities = [linked] }
        await waitForInitialSync()
        api.log.removeAll()

        model.setPriority(linked.id, done: true, day: todayKey)

        let pushed = await waitForLog { $0.contains("patchTask tA - completed") }
        XCTAssertTrue(pushed, "log: \(api.log)")
    }

    func testAddingPriorityInsertsTask() async throws {
        let model = try makeModel()
        await waitForInitialSync()
        api.log.removeAll()

        model.updatePlan(day: todayKey) { $0.priorities.append(Priority(title: "New")) }

        let pushed = await waitForLog { $0.contains { $0.hasPrefix("insertTask New") } }
        XCTAssertTrue(pushed, "log: \(api.log)")
    }

    func testMutatingAnotherDayPushesNothing() async throws {
        let model = try makeModel()
        await waitForInitialSync()
        api.log.removeAll()

        model.updatePlan(day: DayKey.next(todayKey)) { $0.priorities.append(Priority(title: "Tomorrow")) }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertTask") }, "log: \(api.log)")
    }

    func testFinalizedSessionReachesCalendar() async throws {
        let model = try makeModel()
        await waitForInitialSync()
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 25), start: start,
                              end: start.addingTimeInterval(1500), outcome: .completed)

        model.upsertSession(session)

        let logged = await waitForLog { $0.contains { $0.hasPrefix("insertEvent") } }
        XCTAssertTrue(logged, "log: \(api.log)")
    }

    func testHeartbeatUpsertDoesNotLogEvent() async throws {
        let model = try makeModel()
        await waitForInitialSync()
        api.log.removeAll()
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 25),
                              start: Date(timeIntervalSince1970: 1_760_000_000))

        model.upsertSession(session)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertEvent") || $0.hasPrefix("insertCalendar") },
                       "log: \(api.log)")
    }

    func testDisconnectGoogleStopsSyncAndClearsToken() async throws {
        let model = try makeModel()
        XCTAssertTrue(model.isGoogleConnected)

        model.disconnectGoogle()

        XCTAssertFalse(model.isGoogleConnected)
        XCTAssertNil(tokenBox.value)
    }
}
