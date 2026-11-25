import XCTest
@testable import Alcove

/// The end-of-day wrap-up against a connected fake Google: it must never delete or duplicate tasks.
@MainActor final class GoogleWrapUpSyncTests: XCTestCase {
    private final class TokenBox { var value: String? = "rt-1" }

    private let api = FakeGoogleAPI()
    private let tokenBox = TokenBox()
    private var todayKey: String { DayKey.key(for: Date()) }
    private var yesterdayKey: String { DayKey.previous(todayKey) }

    /// A model over a temp store and a connected fake Google, with the calendar pull off.
    private func makeModel(auth: GoogleAuth? = nil) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleWrapUpSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = Store(fileURL: directory.appendingPathComponent("store.json"))
        let box = tokenBox
        let model = AppModel(store: store, engine: EngineHarness().engine,
                             googleAuth: auth ?? GoogleAuth(readToken: { box.value }, writeToken: { box.value = $0 }),
                             googleAPI: api)
        model.updateSettings { $0.googleShowEventsEnabled = false }
        addTeardownBlock { @MainActor in model.googleSync?.stop() }
        return model
    }

    @discardableResult
    private func waitForLog(_ condition: ([String]) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition(api.log) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition(api.log)
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }

    private func task(_ id: String, _ title: String) -> GoogleTask {
        GoogleTask(id: id, title: title, status: "needsAction", completed: nil, due: nil)
    }

    private var deletes: [String] { api.log.filter { $0.hasPrefix("deleteTask") } }
    private var inserts: [String] { api.log.filter { $0.hasPrefix("insertTask") } }

    // MARK: Scenario b: evening wrap-up, then the 4 AM rollover

    func testEveningWrapUpThenRolloverNeitherDeletesNorDuplicates() async throws {
        api.tasks = [task("tA", "A"), task("tB", "B")]
        let model = try makeModel()
        model.updatePlan(day: todayKey) {
            $0.priorities = [Priority(title: "A", googleTaskID: "tA"), Priority(title: "B", googleTaskID: "tB")]
        }
        await waitForLog { $0.contains("listTasks") }
        await settle()
        api.log.removeAll()

        var snapshot = model.todayPlan().priorities
        snapshot[1].isDone = true
        model.wrapUpDay(today: snapshot, tomorrow: [Priority(title: " a "), Priority(title: "New")])

        await waitForLog { $0.contains("patchTask tB - completed") }
        await settle()
        XCTAssertTrue(api.log.contains("patchTask tB - completed"), "\(api.log)")
        XCTAssertTrue(deletes.isEmpty, "\(api.log)")
        XCTAssertTrue(inserts.isEmpty, "tomorrow's items wait for tomorrow: \(api.log)")
        let tomorrow = try XCTUnwrap(model.plan(for: DayKey.next(todayKey)))
        XCTAssertEqual(tomorrow.priorities.map(\.googleTaskID), ["tA", nil], "the carried item keeps its link")

        // 4 AM: tomorrow's plan becomes the synced day.
        api.log.removeAll()
        var rolled = tomorrow
        let sync = GoogleSync(api: api, settings: { model.data.settings }, isConnected: { true },
                              plan: { rolled }, applyPlan: { rolled = $0 }, saveCalendarID: { _ in })
        await sync.syncNow()
        XCTAssertTrue(deletes.isEmpty, "\(api.log)")
        XCTAssertEqual(inserts, ["insertTask New"], "carried items are re-linked, not re-inserted: \(api.log)")
        XCTAssertEqual(rolled.priorities.filter { $0.googleTaskID == "tA" }.count, 1, "\(rolled.priorities)")
    }

    // MARK: Scenario a: yesterday's wrap-up finished after 4 AM

    func testFinishingYesterdayAfterRolloverKeepsTodaysSyncedPlan() async throws {
        api.tasks = [task("tA", "A"), task("tC", "C")]
        let model = try makeModel()
        model.updatePlan(day: yesterdayKey) {
            $0.priorities = [Priority(title: "A", googleTaskID: "tA")]
            $0.wrappedUp = false
        }
        model.updatePlan(day: todayKey) {
            $0.priorities = [Priority(title: "A", googleTaskID: "tA"), Priority(title: "C", googleTaskID: "tC")]
        }
        await waitForLog { $0.contains("listTasks") }
        await settle()
        api.log.removeAll()
        XCTAssertTrue(model.needsPreviousWrapUp())

        model.wrapUpDay(today: model.todayPlan().priorities,
                        tomorrow: [Priority(title: "A"), Priority(title: "New")])

        await waitForLog { $0.contains { $0.hasPrefix("insertTask New") } }
        await settle()
        XCTAssertTrue(deletes.isEmpty, "\(api.log)")
        XCTAssertEqual(inserts, ["insertTask New"], "\(api.log)")
        let today = try XCTUnwrap(model.plan(for: todayKey))
        XCTAssertEqual(today.priorities.map(\.title), ["A", "C", "New"])
        XCTAssertEqual(today.priorities.prefix(2).map(\.googleTaskID), ["tA", "tC"])
        XCTAssertTrue(model.plan(for: yesterdayKey)?.wrappedUp == true)
    }

    // MARK: Scenario c: ticks for the previous day

    func testTickInPreviousDayWrapUpPushesCompletion() async throws {
        api.tasks = [task("tD", "D")]
        let model = try makeModel()
        model.updatePlan(day: yesterdayKey) {
            $0.priorities = [Priority(title: "D", googleTaskID: "tD")]
            $0.wrappedUp = false
        }
        await waitForLog { $0.contains("listTasks") }
        await settle()
        api.log.removeAll()

        var snapshot = model.todayPlan().priorities
        XCTAssertEqual(snapshot.map(\.googleTaskID), ["tD"])
        snapshot[0].isDone = true
        model.wrapUpDay(today: snapshot, tomorrow: [])

        let pushed = await waitForLog { $0.contains("patchTask tD - completed") }
        XCTAssertTrue(pushed, "\(api.log)")
        XCTAssertTrue(deletes.isEmpty, "\(api.log)")
    }

    // MARK: Scenario d: a task pulled while the sheet is open

    func testTaskPulledMidWrapUpSurvivesSave() async throws {
        api.tasks = [task("tA", "A")]
        let model = try makeModel()
        model.updatePlan(day: todayKey) { $0.priorities = [Priority(title: "A", googleTaskID: "tA")] }
        await waitForLog { $0.contains("listTasks") }
        await settle()
        let original = model.todayPlan().priorities
        var edited = original
        edited[0].isDone = true

        // A sync lands while the sheet is open.
        api.tasks.append(task("tB", "B"))
        model.updatePlan(day: todayKey) { $0.priorities.append(Priority(title: "B", googleTaskID: "tB")) }
        api.log.removeAll()

        // The stale snapshot straight to the model, and the sheet's fresh-plan path, both keep B.
        model.wrapUpDay(today: edited, tomorrow: [])
        await waitForLog { $0.contains("patchTask tA - completed") }
        await settle()
        XCTAssertTrue(deletes.isEmpty, "\(api.log)")
        let saved = try XCTUnwrap(model.plan(for: todayKey))
        XCTAssertEqual(saved.priorities.map(\.googleTaskID), ["tA", "tB"])
        XCTAssertEqual(saved.priorities.map(\.isDone), [true, false])

        let fresh = DayPlanner.applyingTicks(edited: edited, original: original, to: saved.priorities)
        XCTAssertEqual(fresh.map(\.googleTaskID), ["tA", "tB"])
        XCTAssertEqual(fresh.map(\.isDone), [true, false])
    }

    // MARK: I1: revocation is observable

    func testRevokedTokenFlipsConnectedFlag() async throws {
        let box = tokenBox
        let transport = MockTransport { _ in (400, MockTransport.json(#"{"error": "invalid_grant"}"#)) }
        let auth = GoogleAuth(transport: transport, readToken: { box.value }, writeToken: { box.value = $0 })
        let model = try makeModel(auth: auth)
        XCTAssertTrue(model.isGoogleConnected)

        _ = try? await auth.accessToken(forceRefresh: true)

        XCTAssertFalse(model.isGoogleConnected)
        XCTAssertNil(tokenBox.value)
    }
}
