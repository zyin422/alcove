import XCTest
@testable import Tofu

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
        let second = Subject(name: "MATH241", preset: .split,
                             sites: ["https://cs128.org", "https://prairielearn.org"],
                             extraDomains: ["piazza.com"], createdAt: t0, colorHex: "F58518")
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

    func testMoveSubjectsReordersAndKeepsTheSelection() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let first = makeSubject("CS128")
        let middle = makeSubject("MATH241")
        let last = makeSubject("CS173")
        model.addSubject(first)
        model.addSubject(middle)
        model.addSubject(last)
        model.selection = .subject(last.id)

        model.moveSubjects(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(model.data.subjects.map(\.name), ["CS173", "CS128", "MATH241"])
        XCTAssertEqual(model.selection, .subject(last.id))

        model.moveSubjects(from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(model.data.subjects.map(\.name), ["CS173", "MATH241", "CS128"])
        XCTAssertEqual(reloaded(store).subjects.map(\.id), [last.id, middle.id, first.id])
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

    func testDeleteSessionRemovesAFinishedBlock() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let session = endedSession(for: makeSubject())
        model.upsertSession(session)

        model.deleteSession(id: session.id)

        XCTAssertTrue(model.data.sessions.isEmpty)
        XCTAssertTrue(reloaded(store).sessions.isEmpty)
    }

    func testDropShortEndedSessionsRemovesFinishedBlocksUnderFiveMinutes() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let short = Session(subjectID: UUID(), subjectName: "MATH241", mode: .open, start: t0,
                            end: t0.addingTimeInterval(120), lastHeartbeat: t0.addingTimeInterval(120),
                            outcome: .bailed)
        let kept = endedSession(for: makeSubject())
        model.upsertSession(short)
        model.upsertSession(kept)

        model.dropShortEndedSessions()

        XCTAssertEqual(model.data.sessions.map(\.id), [kept.id])
        XCTAssertEqual(reloaded(store).sessions.map(\.id), [kept.id])
    }

    func testDeleteSessionLeavesALiveBlockAlone() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let live = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0)
        model.upsertSession(live)

        model.deleteSession(id: live.id)

        XCTAssertEqual(model.data.sessions.map(\.id), [live.id])
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

    // MARK: Chat assistant wiring

    func testModelHooksTheAssistantIntoTheSessionLifecycle() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)
        XCTAssertNotNil(harness.engine.onLockedIn)
        XCTAssertNotNil(harness.engine.onEnded)

        let subject = makeSubject()
        model.addSubject(subject)
        await model.lockIn(subjectID: subject.id, mode: .open)
        XCTAssertTrue(harness.engine.isLocked)
        harness.clock.advance(600)
        await harness.engine.finish()

        XCTAssertFalse(harness.engine.isLocked)
        XCTAssertEqual(model.data.sessions.count, 1)
    }

    func testAssistantNeedingAttentionAsksTheWindowToShowTheChat() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        var shown = 0
        model.onShowChat = { shown += 1 }

        model.assistant.onNeedsAttention?()
        model.assistant.onNeedsAttention?()

        XCTAssertEqual(shown, 2)
    }

    func testAssistantNeedingAttentionWithoutAWindowIsHarmless() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        XCTAssertNil(model.onShowChat)
        XCTAssertNotNil(model.assistant.onNeedsAttention)
        model.assistant.onNeedsAttention?()
    }

    func testModelUsesTheInjectedAssistant() throws {
        let assistant = ChatAssistant(apiKey: { nil })
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine, assistant: assistant)
        XCTAssertTrue(model.assistant === assistant)
    }

    func testConnectLinksTheAssistantAndChromeBothWays() {
        let assistant = ChatAssistant(apiKey: { nil })
        let chrome = ChromeController(judge: FakeJudge(), prompter: FakePrompter())

        AppModel.connect(assistant, with: chrome)

        XCTAssertTrue(chrome.asker === assistant, "unsure sites go to the assistant")
        XCTAssertTrue(assistant.sites === chrome, "allow / close decisions go back to Chrome")
    }

    func testWakingWhileIdleDoesNotTouchTheAssistant() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        var shown = 0
        model.onShowChat = { shown += 1 }

        model.systemDidWake()

        XCTAssertEqual(shown, 0, "no welcome-back chat outside a lock-in")
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

    // MARK: Discord token

    func testResolveTokenKeychainWins() {
        let result = AppModel.resolveToken(keychain: "mine.token", env: "team.token")
        XCTAssertEqual(result.token, "mine.token")
        XCTAssertEqual(result.source, .keychain)
    }

    func testResolveTokenFallsBackToTeamFile() {
        let result = AppModel.resolveToken(keychain: nil, env: "team.token")
        XCTAssertEqual(result.token, "team.token")
        XCTAssertEqual(result.source, .teamFile)
    }

    func testResolveTokenTreatsEmptyStringsAsMissing() {
        let blankKeychain = AppModel.resolveToken(keychain: "", env: "team.token")
        XCTAssertEqual(blankKeychain.token, "team.token")
        XCTAssertEqual(blankKeychain.source, .teamFile)

        let whitespaceKeychain = AppModel.resolveToken(keychain: "  \n", env: "team.token")
        XCTAssertEqual(whitespaceKeychain.source, .teamFile)

        let blankEnv = AppModel.resolveToken(keychain: nil, env: "")
        XCTAssertNil(blankEnv.token)
        XCTAssertEqual(blankEnv.source, .none)
    }

    func testResolveTokenWithoutAnyTokenIsNone() {
        let result = AppModel.resolveToken(keychain: nil, env: nil)
        XCTAssertNil(result.token)
        XCTAssertEqual(result.source, .none)
        XCTAssertEqual(AppModel.resolveToken(keychain: " ", env: "\t").source, .none)
    }

    func testResolveTokenTrimsWhitespace() {
        XCTAssertEqual(AppModel.resolveToken(keychain: "  mine.token \n", env: nil).token, "mine.token")
        XCTAssertEqual(AppModel.resolveToken(keychain: nil, env: "team.token\n").token, "team.token")
    }

    func testTokenSourceLabels() {
        XCTAssertEqual(TokenSource.keychain.label, "Using your token from Keychain")
        XCTAssertEqual(TokenSource.teamFile.label, "Using the team token from .env")
        XCTAssertEqual(TokenSource.none.label, "No token")
    }

    func testModelReadsTokenAndSourceFromItsInjectedSources() throws {
        let team = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                            keychainToken: { nil }, envToken: { "team.token" })
        XCTAssertEqual(team.discordToken, "team.token")
        XCTAssertEqual(team.discordTokenSource, .teamFile)

        let mine = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                            keychainToken: { "mine.token" }, envToken: { "team.token" })
        XCTAssertEqual(mine.discordToken, "mine.token")
        XCTAssertEqual(mine.discordTokenSource, .keychain)

        let none = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        XCTAssertNil(none.discordToken)
        XCTAssertEqual(none.discordTokenSource, .none)
    }

    // MARK: OpenAI key

    func testKeySourceLabels() {
        XCTAssertEqual(TokenSource.keychain.keyLabel, "Using your key from Keychain")
        XCTAssertEqual(TokenSource.teamFile.keyLabel, "Using the team key from .env")
        XCTAssertEqual(TokenSource.none.keyLabel, "No key — you'll be asked about each site")
    }

    func testOpenAIKeyComesFromItsOwnInjectedSources() throws {
        let team = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                            keychainOpenAIKey: { nil }, envOpenAIKey: { "sk-team\n" })
        XCTAssertEqual(team.openAIKey, "sk-team")
        XCTAssertEqual(team.openAIKeySource, .teamFile)

        let mine = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                            keychainOpenAIKey: { " sk-mine " }, envOpenAIKey: { "sk-team" })
        XCTAssertEqual(mine.openAIKey, "sk-mine", "the Keychain key wins and is trimmed")
        XCTAssertEqual(mine.openAIKeySource, .keychain)

        let blankKeychain = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                                     keychainOpenAIKey: { "  " }, envOpenAIKey: { "sk-team" })
        XCTAssertEqual(blankKeychain.openAIKey, "sk-team")
        XCTAssertEqual(blankKeychain.openAIKeySource, .teamFile)

        let none = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        XCTAssertNil(none.openAIKey)
        XCTAssertEqual(none.openAIKeySource, .none)
    }

    func testOpenAIKeyDoesNotMixWithTheDiscordToken() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                             keychainToken: { "discord.token" }, envToken: { "team.token" })
        XCTAssertEqual(model.discordToken, "discord.token")
        XCTAssertNil(model.openAIKey)
        XCTAssertEqual(model.openAIKeySource, .none)
    }

    func testOpenAIKeyIsReadOnEveryAccessSoASavedKeyAppliesImmediately() throws {
        var saved: String?
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine,
                             keychainOpenAIKey: { saved })
        XCTAssertNil(model.openAIKey)
        saved = "sk-new"
        XCTAssertEqual(model.openAIKey, "sk-new")
        XCTAssertEqual(model.openAIKeySource, .keychain)
    }

    func testOpenAIKeychainCoordinatesDifferFromDiscords() {
        XCTAssertEqual(Secrets.openAIService, "com.tofu.openai")
        XCTAssertEqual(Secrets.openAIAccount, "api-key")
        XCTAssertNotEqual(Secrets.openAIService, Secrets.discordService)
    }

    func testFirstLaunchWithATokenTurnsDiscordOnAndSaves() throws {
        let store = try makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))

        let model = AppModel(store: store, engine: EngineHarness().engine,
                             keychainToken: { nil }, envToken: { "team.token" })

        XCTAssertTrue(model.data.settings.discordEnabled)
        XCTAssertTrue(reloaded(store).settings.discordEnabled)
    }

    func testFirstLaunchWithAKeychainTokenTurnsDiscordOn() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine,
                             keychainToken: { "mine.token" }, envToken: { nil })

        XCTAssertTrue(model.data.settings.discordEnabled)
        XCTAssertTrue(reloaded(store).settings.discordEnabled)
    }

    func testFirstLaunchWithoutATokenLeavesDiscordOffAndWritesNothing() throws {
        let store = try makeStore()

        let model = AppModel(store: store, engine: EngineHarness().engine,
                             keychainToken: { "  " }, envToken: { "" })

        XCTAssertFalse(model.data.settings.discordEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testLaterLaunchesNeverTurnDiscordOnByThemselves() throws {
        let store = try makeStore()
        try store.save(StoreData(subjects: [makeSubject()]))   // the store file exists: not a first launch

        let model = AppModel(store: store, engine: EngineHarness().engine,
                             keychainToken: { nil }, envToken: { "team.token" })

        XCTAssertFalse(model.data.settings.discordEnabled)
        XCTAssertFalse(reloaded(store).settings.discordEnabled)
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

    func testSitesAndAppsAllowedDuringABlockAreSaved() async throws {
        let store = try makeStore()
        let harness = EngineHarness()
        let model = AppModel(store: store, engine: harness.engine)
        let subject = makeSubject()
        model.addSubject(subject)
        await harness.engine.start(subject: subject, mode: .open, displayName: "Z")
        harness.engine.lookupApp = { name in
            name == "Calculator" ? AllowedApp(bundleID: "com.apple.calculator", name: "Calculator") : nil
        }

        harness.engine.rememberAllowedSite("https://stackoverflow.com/questions/1")
        XCTAssertEqual(harness.engine.allowApp(named: "Calculator"), "Allowed Calculator for this work block.")

        let saved = model.subject(id: subject.id)
        XCTAssertEqual(saved?.extraDomains, ["piazza.com", "stackoverflow.com"])
        XCTAssertEqual(saved?.allowedApps.map(\.name), ["Calculator"])
        let again = reloaded(store).subjects.first { $0.id == subject.id }
        XCTAssertEqual(again?.extraDomains, ["piazza.com", "stackoverflow.com"])
        XCTAssertEqual(again?.allowedApps.map(\.bundleID), ["com.apple.calculator"])
    }
}
