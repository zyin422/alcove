import SwiftUI
import XCTest
@testable import Tofu

final class MorningTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func shouldShow(at now: Date, settings: AppSettings = AppSettings(), isLocked: Bool = false,
                            isBusy: Bool = false, hasStartedBlock: Bool = false, postponeUntil: Date? = nil) -> Bool {
        DayPlanner.shouldShowMorning(now: now, settings: settings, isLocked: isLocked, isBusy: isBusy,
                                     hasStartedBlock: hasStartedBlock, postponeUntil: postponeUntil, calendar: calendar)
    }

    func testPickPriorityScreenCoversEveryDisplay() {
        let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        XCTAssertEqual(MorningWindowPolicy.frames(covering: [laptop, external, .zero]), [laptop, external])
    }

    func testQuitIsRefusedDuringABlock() {
        XCTAssertFalse(QuitPolicy.allowsQuit(isLocked: true))
        XCTAssertTrue(QuitPolicy.allowsQuit(isLocked: false))
    }

    func testForceQuitWatchRestartsOnlyWhileTheFlagExists() {
        let text = BlockGuard.plist(script: "/tmp/block-guard.sh", flag: "/tmp/block-open")
        XCTAssertTrue(text.contains(BlockGuard.label))
        XCTAssertTrue(text.contains("<key>/tmp/block-open</key>"))
        XCTAssertTrue(text.contains("<key>PathState</key>"))
        XCTAssertTrue(text.contains("/tmp/block-guard.sh"))
    }

    func testShowsOncePerDayFromFourAM() {
        XCTAssertTrue(shouldShow(at: date(11, 7)))
        XCTAssertTrue(shouldShow(at: date(11, 4)))
        XCTAssertFalse(shouldShow(at: date(11, 7), hasStartedBlock: true))
        XCTAssertTrue(shouldShow(at: date(12, 7)))
        XCTAssertFalse(shouldShow(at: date(11, 7), postponeUntil: date(11, 7, 10)))
        XCTAssertTrue(shouldShow(at: date(11, 7, 10), postponeUntil: date(11, 7, 10)))
    }

    func testNotLateAtNightLockedBusyOrOff() {
        XCTAssertFalse(shouldShow(at: date(11, 23)))
        XCTAssertFalse(shouldShow(at: date(12, 1)), "1 AM still belongs to the evening before")
        XCTAssertFalse(shouldShow(at: date(11, 7), isLocked: true))
        XCTAssertFalse(shouldShow(at: date(11, 7), isBusy: true))
        XCTAssertFalse(shouldShow(at: date(11, 7), settings: AppSettings(morningScreenEnabled: false)))
    }

    func testGreeting() {
        XCTAssertEqual(DayPlanner.greeting(at: date(11, 7), calendar: calendar), "Good morning")
        XCTAssertEqual(DayPlanner.greeting(at: date(11, 13), calendar: calendar), "Good afternoon")
        XCTAssertEqual(DayPlanner.greeting(at: date(11, 19), calendar: calendar), "Good evening")
    }

    func testOldSettingsDecodeWithTheMorningScreenOn() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"displayName":"Z"}"#.utf8))
        XCTAssertTrue(settings.morningScreenEnabled)
        XCTAssertNil(settings.lastMorningKey)
    }

    // MARK: Model

    @MainActor private func makeModel(_ harness: EngineHarness) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Morning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppModel(store: Store(fileURL: directory.appendingPathComponent("store.json")), engine: harness.engine)
    }

    @MainActor func testMorningPostponeDelaysTenMinutes() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        var shown = 0
        model.onShowMorning = { shown += 1 }
        model.updateSettings { $0.dayEndMinutes = 28 * 60 }   // never "too late" during the test (full 4 AM - 4 AM cycle)
        model.checkMorning(now: now)
        XCTAssertEqual(shown, 1)
        XCTAssertTrue(model.isShowingMorning)
        XCTAssertTrue(model.canPostponeMorning)
        XCTAssertNil(model.data.settings.lastMorningKey)
        XCTAssertNil(model.data.settings.lastPostponeKey)

        model.postponeMorning(by: 600, now: now)
        XCTAssertFalse(model.isShowingMorning)
        XCTAssertEqual(model.data.settings.lastPostponeKey, DayKey.key(for: now))
        XCTAssertFalse(model.canPostponeMorning)

        model.checkMorning(now: now.addingTimeInterval(60))
        XCTAssertEqual(shown, 1, "the ten minutes are still running")

        model.checkMorning(now: now.addingTimeInterval(600))
        XCTAssertEqual(shown, 2)
        XCTAssertTrue(model.isShowingMorning)
        XCTAssertFalse(model.canPostponeMorning, "only once per day")

        // Spamming postpone is prevented: screen stays up
        model.postponeMorning(by: 600, now: now.addingTimeInterval(600))
        XCTAssertTrue(model.isShowingMorning, "cannot spam postpone")

        // Next day allows postpone again
        let tomorrow = now.addingTimeInterval(24 * 3600)
        XCTAssertTrue(model.allowsMorningPostpone(now: tomorrow))
    }

    @MainActor func testOpenPlanPostponesLockInAndSelectsToday() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        model.showMorning(now: now)
        XCTAssertTrue(model.isShowingMorning)

        var mainWindowShown = false
        model.onShowMainWindow = { mainWindowShown = true }

        model.openPlan(now: now)
        XCTAssertFalse(model.isShowingMorning)
        XCTAssertEqual(model.selection, .today)
        XCTAssertTrue(mainWindowShown)
        XCTAssertEqual(model.data.settings.morningPostponeUntil, now.addingTimeInterval(600))
        XCTAssertEqual(model.data.settings.lastPostponeKey, DayKey.key(for: now))
    }

    @MainActor func testBetweenBlocksSyncAndDeadlinesWhenPostponing() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        var syncCalled = false
        model.onSyncBetweenBlocks = { syncCalled = true }

        model.showMorning(now: now)
        model.openPlan(now: now)

        XCTAssertTrue(syncCalled, "Opening plan must trigger between-blocks mini-timer sync")
        XCTAssertNotNil(model.nextForceBlockDeadline)
        XCTAssertEqual(model.nextForceBlockReason, "10-minute postpone active")
        XCTAssertGreaterThan(model.secondsUntilNextForceBlock ?? 0, 500)
    }

    @MainActor func testStartTiesThePriorityToTheSetupAndLocksIn() async throws {
        let harness = EngineHarness()
        let model = try makeModel(harness)
        let subject = Subject(name: "CS128", sites: ["https://cs128.org"])
        model.addSubject(subject)
        let priority = Priority(title: "Finish the lab")
        model.updatePlan(day: DayKey.key(for: Date())) { $0.priorities = [priority] }
        model.showMorning()

        await model.start(priority: priority, subjectID: subject.id, mode: .goal(minutes: 50))

        XCTAssertFalse(model.isShowingMorning)
        XCTAssertEqual(model.todayPlan().priorities.first?.subjectID, subject.id)
        XCTAssertEqual(harness.engine.subject?.id, subject.id)
        XCTAssertEqual(harness.chrome.preparedSites, ["https://cs128.org"])
    }

    @MainActor func testStartDirectSubjectLocksInWithoutAPriority() async throws {
        let harness = EngineHarness()
        let model = try makeModel(harness)
        let subject = Subject(name: "MATH241", sites: ["https://desmos.com"])
        model.addSubject(subject)
        model.showMorning()

        await model.start(subjectID: subject.id, mode: .goal(minutes: 25))

        XCTAssertFalse(model.isShowingMorning)
        XCTAssertEqual(harness.engine.subject?.id, subject.id)
        XCTAssertEqual(harness.chrome.preparedSites, ["https://desmos.com"])
    }

    @MainActor func testMorningViewRendersWithOtherSubjects() throws {
        let harness = EngineHarness()
        let model = try makeModel(harness)
        let subject1 = Subject(name: "CS128", sites: ["https://cs128.org"])
        let subject2 = Subject(name: "MATH241", sites: ["https://desmos.com"])
        model.addSubject(subject1)
        model.addSubject(subject2)
        let priority = Priority(title: "Finish CS128 lab", subjectID: subject1.id)
        model.updatePlan(day: DayKey.key(for: Date())) { $0.priorities = [priority] }

        let view = MorningView(model: model)
            .frame(width: 800, height: 600)
        let renderer = ImageRenderer(content: view)
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor func testMorningViewRendersWithNoPrioritiesDirectSubjects() throws {
        let harness = EngineHarness()
        let model = try makeModel(harness)
        let subject = Subject(name: "MATH241", sites: ["https://desmos.com"])
        model.addSubject(subject)

        let view = MorningView(model: model)
            .frame(width: 800, height: 600)
        let renderer = ImageRenderer(content: view)
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor func testStartAfterWrapUpUsesTomorrowsPriority() async throws {
        let harness = EngineHarness()
        let model = try makeModel(harness)
        let subject = Subject(name: "CS173", sites: ["https://cs173.org"])
        model.addSubject(subject)
        let now = Date()
        let tomorrow = Priority(title: "CS173")
        model.wrapUpDay(today: [Priority(title: "Old lab", isDone: true)], tomorrow: [tomorrow], now: now)

        XCTAssertEqual(model.plan(for: DayKey.key(for: now))?.priorities.map(\.title), ["Old lab"])
        XCTAssertTrue(model.plan(for: DayKey.key(for: now))?.wrappedUp == true)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["Old lab"])

        let nextMorning = DayKey.date(for: DayKey.tomorrow(from: now))!
        XCTAssertEqual(model.todayPlan(now: nextMorning).priorities.map(\.title), ["CS173"])
        model.startMyDay(now: nextMorning)
        XCTAssertTrue(model.isShowingMorning)
        XCTAssertEqual(model.todayPlan(now: nextMorning).priorities.map(\.title), ["CS173"])

        await model.start(priority: tomorrow, subjectID: subject.id, mode: .goal(minutes: 50), now: nextMorning)

        XCTAssertEqual(model.todayPlan(now: nextMorning).priorities.first?.subjectID, subject.id)
        XCTAssertEqual(harness.engine.subject?.id, subject.id)
    }

    @MainActor func testCheckMorningOpensYesterdaysWrapUpInstead() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        model.updatePlan(day: DayKey.previous(DayKey.key(for: now))) { $0.priorities = [Priority(title: "Lab")] }
        model.updateSettings { $0.dayEndMinutes = 28 * 60 }
        var shown = 0
        model.onShowMorning = { shown += 1 }

        model.checkMorning(now: now)

        XCTAssertEqual(shown, 0)
        XCTAssertTrue(model.isWrappingUpDay)
        XCTAssertFalse(model.isShowingMorning)
        XCTAssertNil(model.data.settings.lastMorningKey)
    }

    func testAShortBlockBringsTheScreenStraightBack() {
        let now = date(11, 10)
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                              start: date(11, 9, 58), end: now, outcome: .completed)
        let prompt = DayPlanner.morningPrompt(
            now: now, settings: AppSettings(dayEndMinutes: 22 * 60), isLocked: false, isBusy: false,
            wrappedUp: false, sessions: [session], quiet: [], graceUntil: nil, graceHeld: false, calendar: calendar)
        XCTAssertTrue(prompt.show)
        XCTAssertTrue(prompt.postponeAllowed)
        XCTAssertNil(prompt.waitUntil)
    }

    func testPostponeNotAllowedWhenAlreadyUsedToday() {
        let now = date(11, 10)
        let today = DayKey.key(for: now, calendar: calendar)
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                              start: date(11, 9, 58), end: now, outcome: .completed)
        let prompt = DayPlanner.morningPrompt(
            now: now, settings: AppSettings(dayEndMinutes: 22 * 60, lastPostponeKey: today), isLocked: false, isBusy: false,
            wrappedUp: false, sessions: [session], quiet: [], graceUntil: nil, graceHeld: false, calendar: calendar)
        XCTAssertTrue(prompt.show)
        XCTAssertFalse(prompt.postponeAllowed)
        XCTAssertNil(prompt.waitUntil)
    }

    func testARealBlockWaitsThroughGraceAndACalendarEvent() {
        let blockEnd = date(11, 8, 30)
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                              start: date(11, 8), end: blockEnd, outcome: .completed)
        let during = DayPlanner.morningPrompt(
            now: date(11, 8, 40), settings: AppSettings(), isLocked: false, isBusy: false, wrappedUp: false,
            sessions: [session], quiet: [], graceUntil: nil, graceHeld: false, calendar: calendar)
        XCTAssertFalse(during.show)
        XCTAssertEqual(during.waitUntil, blockEnd.addingTimeInterval(DayPlanner.betweenBlockGrace))

        let event = DayPlanner.QuietInterval(start: date(11, 9), end: date(11, 11))
        let inClass = DayPlanner.morningPrompt(
            now: date(11, 10), settings: AppSettings(), isLocked: false, isBusy: false, wrappedUp: false,
            sessions: [session], quiet: [event], graceUntil: during.graceUntil, graceHeld: false, calendar: calendar)
        XCTAssertFalse(inClass.show)
        XCTAssertEqual(inClass.waitUntil, date(11, 11).addingTimeInterval(DayPlanner.betweenBlockGrace))

        let wrapped = DayPlanner.morningPrompt(
            now: date(11, 12), settings: AppSettings(), isLocked: false, isBusy: false, wrappedUp: true,
            sessions: [session], quiet: [], graceUntil: inClass.graceUntil, graceHeld: false, calendar: calendar)
        XCTAssertFalse(wrapped.show)
    }

    @MainActor func testAShortBlockReturnsAndARealBlockGracePausesWhileAsleep() throws {
        let model = try makeModel(EngineHarness())
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 15))!
        model.updateSettings { $0.dayEndMinutes = 24 * 60 + 3 * 60 }
        var shown = 0
        model.onShowMorning = { shown += 1 }

        model.upsertSession(Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                                    start: now.addingTimeInterval(-120), end: now, outcome: .completed))
        model.checkMorning(now: now)
        XCTAssertEqual(shown, 1)
        XCTAssertTrue(model.allowsMorningPostpone(now: now))
        model.dismissMorning()

        let realEnd = now.addingTimeInterval(600)
        model.upsertSession(Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                                    start: now, end: realEnd, outcome: .completed))
        model.checkMorning(now: realEnd)
        XCTAssertEqual(shown, 1, "the 20 minutes are still running")
        XCTAssertEqual(model.data.settings.morningGraceUntil, realEnd.addingTimeInterval(DayPlanner.betweenBlockGrace))

        model.holdMorningGrace(now: realEnd.addingTimeInterval(5 * 60))
        let wake = realEnd.addingTimeInterval(3 * 3600)
        model.checkMorning(now: wake)
        XCTAssertEqual(shown, 1)
        XCTAssertNil(model.data.settings.morningGraceHeld)
        XCTAssertEqual(model.data.settings.morningGraceUntil, wake.addingTimeInterval(15 * 60))
        model.checkMorning(now: wake.addingTimeInterval(15 * 60))
        XCTAssertEqual(shown, 2)
        XCTAssertTrue(model.allowsMorningPostpone(now: wake.addingTimeInterval(15 * 60)))

        model.dismissMorning()
        model.updatePlan(day: DayKey.key(for: wake)) { $0.wrappedUp = true }
        model.checkMorning(now: wake.addingTimeInterval(16 * 60))
        XCTAssertEqual(shown, 2, "wrap up ends the day")
    }

    @MainActor func testAWrappedDayAsksAgainAtTheNextMorning() throws {
        let model = try makeModel(EngineHarness())
        let evening = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 22, minute: 30))!
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        model.updateSettings { $0.dayEndMinutes = 24 * 60 + 3 * 60 }
        model.updatePlan(day: DayKey.key(for: evening)) { $0.wrappedUp = true }
        var shown = 0
        model.onShowMorning = { shown += 1 }

        model.checkMorning(now: evening)
        XCTAssertEqual(shown, 0)
        XCTAssertEqual(model.data.settings.morningGraceUntil, nil)

        let prompt = DayPlanner.morningPrompt(
            now: evening, settings: model.data.settings, isLocked: false, isBusy: false, wrappedUp: true,
            sessions: [], quiet: [], graceUntil: nil, graceHeld: false)
        XCTAssertEqual(prompt.waitUntil, DayKey.nextStart(after: evening))

        model.checkMorning(now: morning)
        XCTAssertEqual(shown, 1)
        model.checkMorning(now: morning.addingTimeInterval(60))
        XCTAssertEqual(shown, 2, "a wake that found the screen already flagged still brings it forward")
    }

    @MainActor func testNextForceBlockCountdownTelemetry() async throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        
        // When not locked in, postpone sets next force block
        model.postponeMorning(by: 600, now: now)
        XCTAssertNotNil(model.nextForceBlockDeadline)
        XCTAssertEqual(model.nextForceBlockReason, "10-minute postpone active")
        if let seconds = model.secondsUntilNextForceBlock {
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertLessThanOrEqual(seconds, 600)
        }

        // When locked in, deadline is nil
        await model.engine.start(subject: Subject(name: "CS128"), mode: .open, displayName: "Alex")
        XCTAssertNil(model.nextForceBlockDeadline)
        XCTAssertNil(model.secondsUntilNextForceBlock)
    }

    @MainActor func testMorningPrioritySelectionDefaults() throws {
        let model = try makeModel(EngineHarness())
        let p1 = Priority(title: "CS225 Lab", estimatedMinutes: 50)
        let p2 = Priority(title: "Read Paper", estimatedMinutes: 30)
        model.updatePlan(day: DayKey.key(for: Date())) {
            $0.priorities = [p1, p2]
        }

        let plan = model.todayPlan()
        XCTAssertEqual(plan.priorities.first?.title, "CS225 Lab")
        XCTAssertFalse(plan.priorities.first?.isDone == true)
    }

    @MainActor func testStudyCompletedSuppressesMorningPromptAndDeadline() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        let today = DayKey.key(for: now)
        let subject = Subject(name: "CS128")
        model.addSubject(subject)

        let p1 = Priority(title: "CS128 Lab", subjectID: subject.id, isDone: false)
        let p2 = Priority(title: "Math PSet", isDone: false)
        model.updatePlan(day: today) { $0.priorities = [p1, p2] }

        XCTAssertFalse(model.isStudyCompleted(day: today, now: now))

        var shown = 0
        model.onShowMorning = { shown += 1 }

        // Finish subject priority CS128 Lab
        model.setPriority(p1.id, done: true, day: today)
        XCTAssertFalse(model.isStudyCompleted(day: today, now: now))

        // Finish remaining priority Math PSet
        model.setPriority(p2.id, done: true, day: today)
        XCTAssertTrue(model.isStudyCompleted(day: today, now: now))

        // checkMorning should NOT show the morning screen
        model.checkMorning(now: now)
        XCTAssertEqual(shown, 0, "completed study subjects must suppress the morning screen")

        // Force-block deadline must be nil so no countdown or restriction is imposed
        XCTAssertNil(model.nextForceBlockDeadline)
        XCTAssertNil(model.secondsUntilNextForceBlock)
    }

    @MainActor func testStudyCompletedDismissesActiveMorningScreen() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        let today = DayKey.key(for: now)
        let priority = Priority(title: "Lab Report", isDone: false)
        model.updatePlan(day: today) { $0.priorities = [priority] }

        var hidden = 0
        model.onHideMorning = { hidden += 1 }

        // Simulate morning screen already active
        model.showMorning(now: now)
        XCTAssertTrue(model.isShowingMorning)

        // Mark the priority done
        model.setPriority(priority.id, done: true, day: today)

        XCTAssertTrue(model.isStudyCompleted(day: today, now: now))
        XCTAssertFalse(model.isShowingMorning, "completing study subjects must dismiss active morning screen")
        XCTAssertEqual(hidden, 1)
    }

    @MainActor func testStudyCompletedWhenAllActiveSubjectsStudiedWithoutPriorities() throws {
        let model = try makeModel(EngineHarness())
        let now = date(11, 14)
        let today = DayKey.key(for: now)
        let s1 = Subject(name: "CS128")
        let s2 = Subject(name: "MATH241")
        model.addSubject(s1)
        model.addSubject(s2)

        // No priorities in today's plan
        model.updatePlan(day: today) { $0.priorities = [] }
        XCTAssertFalse(model.isStudyCompleted(day: today, now: now))

        // Record a finished session for s1 only
        let sess1 = Session(subjectID: s1.id, subjectName: "CS128", mode: .open,
                            start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800))
        model.upsertSession(sess1)
        XCTAssertFalse(model.isStudyCompleted(day: today, now: now))

        // Record a finished session for s2
        let sess2 = Session(subjectID: s2.id, subjectName: "MATH241", mode: .open,
                            start: now.addingTimeInterval(-1200), end: now.addingTimeInterval(-300))
        model.upsertSession(sess2)

        XCTAssertTrue(model.isStudyCompleted(day: today, now: now),
                      "when all configured subjects have completed sessions today, study is completed")
    }

    @MainActor func testScheduledBetweenBlockReturnAutomaticallyShowsForceLockIn() throws {
        let model = try makeModel(EngineHarness())
        model.updateSettings {
            $0.morningScreenEnabled = true
            $0.bedtimeGuardEnabled = false // isolate daytime between-block lock-in from nocturnal bedtime guard
            $0.dayEndMinutes = 28 * 60 // covers past-midnight testing across the full 4 AM - 4 AM DayKey cycle
        }
        let s1 = Subject(name: "CS128")
        model.addSubject(s1)
        let now = Date()
        let today = DayKey.key(for: now)
        model.updatePlan(day: today) {
            $0.priorities = [Priority(title: "Finish lab", subjectID: s1.id, isDone: false)]
        }

        let shown = expectation(description: "force lock-in automatically appears when timer expires")
        model.onShowMorning = { shown.fulfill() }

        // Postpone / grace expires in 0.15s; timer must fire automatically without another manual checkMorning().
        model.postponeMorning(by: 0.15, now: now)
        XCTAssertFalse(model.isShowingMorning)

        wait(for: [shown], timeout: 2.0)
        XCTAssertTrue(model.isShowingMorning)
    }

    @MainActor func testStudyCompletedCelebratesOncePerDay() throws {
        let model = try makeModel(EngineHarness())
        let now = Date()
        let today = DayKey.key(for: now)
        let p1 = Priority(title: "First task", isDone: false)
        model.updatePlan(day: today) { $0.priorities = [p1] }

        var callbacks = 0
        model.onStudyCompleted = { callbacks += 1 }
        model.setPriority(p1.id, done: true, day: today)
        XCTAssertEqual(model.data.settings.lastStudyCelebratedDay, today)
        XCTAssertEqual(callbacks, 1)

        // Adding and completing another priority later the same day must not re-celebrate in settings.
        let p2 = Priority(title: "Added later", isDone: false)
        model.updatePlan(day: today) { $0.priorities.append(p2) }
        model.setPriority(p2.id, done: true, day: today)
        XCTAssertEqual(model.data.settings.lastStudyCelebratedDay, today)
    }

    func testActivePriorityPreferredForMorningAndMiniTimerCaption() {
        let sub = UUID()
        let first = Priority(title: "Routine task", subjectID: sub, isDone: false, isAnchor: false)
        let second = Priority(title: "Anchored task", subjectID: sub, isDone: false, isAnchor: true)
        let plan = DayPlan(day: "2026-11-25", priorities: [first, second])
        XCTAssertEqual(plan.activePriority(for: sub)?.id, second.id)
    }
}
