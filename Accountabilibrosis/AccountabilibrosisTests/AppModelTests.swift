import XCTest
@testable import Accountabilibrosis

@MainActor
final class AppModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)   // whole seconds: ISO8601 keeps them exactly

    /// A Store in a fresh temp directory that is deleted after the test (the real store.json is never touched).
    private func makeStore() throws -> Store {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Store(fileURL: directory.appendingPathComponent("store.json"))
    }

    /// What a fresh launch would read back from the same file.
    private func reloaded(_ store: Store) -> StoreData {
        Store(fileURL: store.fileURL).load().data
    }

    private func makeSubject(_ name: String = "CS128") -> Subject {
        Subject(name: name, preset: .split, sites: ["https://cs128.org", "https://prairielearn.org"],
                extraDomains: ["piazza.com"], createdAt: t0)
    }

    private func endedSession(for subject: Subject, isDemo: Bool = false) -> Session {
        Session(subjectID: subject.id, subjectName: subject.name, mode: .goal(minutes: 25), start: t0,
                end: t0.addingTimeInterval(1500), outcome: .completed, isDemo: isDemo)
    }

    // MARK: Loading

    func testFreshStoreStartsEmptyWithNoSelection() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        XCTAssertEqual(model.data, StoreData.empty)
        XCTAssertNil(model.selection)
    }

    func testSelectionDefaultsToFirstSubject() throws {
        let store = try makeStore()
        let first = makeSubject("CS128")
        let second = makeSubject("MATH241")
        try store.save(StoreData(subjects: [first, second]))

        let model = AppModel(store: store, engine: EngineHarness().engine)

        XCTAssertEqual(model.data.subjects, [first, second])
        XCTAssertEqual(model.selection, .subject(first.id))
    }

    // MARK: Subjects

    func testAddSubjectPersistsAndSelectsIt() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let subject = makeSubject()

        model.addSubject(subject)

        XCTAssertEqual(model.selection, .subject(subject.id))
        XCTAssertEqual(model.subject(id: subject.id), subject)
        XCTAssertEqual(reloaded(store).subjects, [subject])
    }

    func testUpdateSubjectPersists() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        var subject = makeSubject()
        model.addSubject(subject)

        subject.name = "CS 128"
        subject.preset = .full
        subject.sites = ["https://cs128.org"]
        model.updateSubject(subject)

        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertEqual(reloaded(store).subjects, [subject])
    }

    func testUpdateUnknownSubjectChangesNothing() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        model.addSubject(makeSubject())

        model.updateSubject(makeSubject("Ghost"))

        XCTAssertEqual(model.data.subjects.map(\.name), ["CS128"])
    }

    func testDeleteSubjectKeepsItsSessionsAndMovesSelection() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let doomed = makeSubject("CS128")
        let kept = makeSubject("MATH241")
        model.addSubject(doomed)
        model.addSubject(kept)
        model.upsertSession(endedSession(for: doomed))
        model.selection = .subject(doomed.id)

        model.deleteSubject(id: doomed.id)

        XCTAssertEqual(model.selection, .subject(kept.id))
        let data = reloaded(store)
        XCTAssertEqual(data.subjects, [kept])
        XCTAssertEqual(data.sessions.count, 1)
        XCTAssertEqual(data.sessions.first?.subjectName, "CS128")
    }

    func testDeletingLastSubjectClearsSelection() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        let subject = makeSubject()
        model.addSubject(subject)

        model.deleteSubject(id: subject.id)

        XCTAssertNil(model.selection)
        XCTAssertTrue(model.data.subjects.isEmpty)
    }

    // MARK: Sessions

    func testUpsertSessionInsertsThenUpdates() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        var session = endedSession(for: makeSubject())

        model.upsertSession(session)
        session.closedTabs = 3
        session.blockedAttempts = 2
        model.upsertSession(session)

        XCTAssertEqual(model.data.sessions, [session])
        XCTAssertEqual(reloaded(store).sessions, [session])
    }

    func testEngineSessionChangesArePersisted() async throws {
        let store = try makeStore()
        let harness = EngineHarness()
        let model = AppModel(store: store, engine: harness.engine)
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .open)

        XCTAssertTrue(harness.engine.isLocked)
        let active = try XCTUnwrap(model.data.sessions.first)
        XCTAssertEqual(model.data.sessions.count, 1)
        XCTAssertNil(active.end)
        XCTAssertEqual(reloaded(store).sessions.map(\.id), [active.id])

        harness.clock.advance(600)
        await harness.engine.finish()

        let saved = try XCTUnwrap(reloaded(store).sessions.first)
        XCTAssertEqual(saved.id, active.id)
        XCTAssertEqual(saved.outcome, .completed)
        XCTAssertEqual(saved.duration, 600)
        XCTAssertEqual(model.data.sessions, [saved])
    }

    func testLockInPassesDisplayNameToTheEngine() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)
        model.updateSettings { $0.displayName = "Alex" }
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .goal(minutes: 25))

        XCTAssertEqual(harness.announcer.messages,
                       [DiscordMessages.start(name: "Alex", subject: "CS128", mode: .goal(minutes: 25))])
        XCTAssertTrue(harness.announcer.messages[0].contains("**Alex**"))
    }

    func testLockInWithBlankDisplayNameFallsBackToFullUserName() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)
        model.updateSettings { $0.displayName = "   " }
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .open)

        XCTAssertEqual(harness.announcer.messages,
                       [DiscordMessages.start(name: NSFullUserName(), subject: "CS128", mode: .open)])
    }

    func testLockInUnknownSubjectDoesNothing() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)

        await model.lockIn(subjectID: UUID(), mode: .open)

        XCTAssertFalse(harness.engine.isLocked)
        XCTAssertEqual(harness.announcer.messages, [])
        XCTAssertTrue(model.data.sessions.isEmpty)
    }

    // MARK: Settings

    func testUpdateSettingsPersists() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)

        model.updateSettings {
            $0.displayName = "Sam"
            $0.discordEnabled = true
            $0.giveUpTemplate = "I quit {subject}"
        }

        let settings = reloaded(store).settings
        XCTAssertEqual(settings.displayName, "Sam")
        XCTAssertTrue(settings.discordEnabled)
        XCTAssertEqual(settings.giveUpTemplate, "I quit {subject}")
    }

    // MARK: Demo data

    func testLoadDemoDataCreatesDefaultSubjectsWhenThereAreNone() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)

        model.loadDemoData()

        XCTAssertEqual(model.data.subjects.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(model.selection, model.data.subjects.first.map { .subject($0.id) })
        XCTAssertFalse(model.data.sessions.isEmpty)
        XCTAssertTrue(model.data.sessions.allSatisfy { $0.isDemo && $0.end != nil })
        XCTAssertEqual(reloaded(store).sessions.count, model.data.sessions.count)
    }

    func testLoadDemoDataUsesExistingSubjectsAndNeverDuplicates() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        let subject = makeSubject("PHYS211")
        model.addSubject(subject)

        model.loadDemoData()
        model.loadDemoData()

        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertFalse(model.data.sessions.isEmpty)
        XCTAssertTrue(model.data.sessions.allSatisfy { $0.subjectID == subject.id && $0.subjectName == "PHYS211" })
        let ids = model.data.sessions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testClearDemoDataRemovesOnlyDemoSessions() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let subject = makeSubject()
        model.addSubject(subject)
        let real = endedSession(for: subject)
        model.upsertSession(real)
        model.loadDemoData()
        XCTAssertGreaterThan(model.data.sessions.count, 1)

        model.clearDemoData()

        XCTAssertEqual(model.data.sessions, [real])
        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertEqual(reloaded(store).sessions, [real])
    }
}
