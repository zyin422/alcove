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
                            isBusy: Bool = false) -> Bool {
        DayPlanner.shouldShowMorning(now: now, settings: settings, isLocked: isLocked, isBusy: isBusy, calendar: calendar)
    }

    func testShowsOncePerDayFromFourAM() {
        XCTAssertTrue(shouldShow(at: date(11, 7)))
        XCTAssertTrue(shouldShow(at: date(11, 4)))
        XCTAssertFalse(shouldShow(at: date(11, 7), settings: AppSettings(lastMorningKey: "2026-10-11")))
        XCTAssertTrue(shouldShow(at: date(12, 7), settings: AppSettings(lastMorningKey: "2026-10-11")))
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

    @MainActor func testCheckMorningShowsOnceAndMarksTheDay() throws {
        let model = try makeModel(EngineHarness())
        var shown = 0
        model.onShowMorning = { shown += 1 }
        model.updateSettings { $0.dayEndMinutes = 24 * 60 + 3 * 60 }   // never "too late" during the test
        model.checkMorning()
        model.checkMorning()
        XCTAssertEqual(shown, 1)
        XCTAssertTrue(model.isShowingMorning)
        XCTAssertEqual(model.data.settings.lastMorningKey, DayKey.key(for: Date()))
        var hidden = 0
        model.onHideMorning = { hidden += 1 }
        model.dismissMorning()
        model.checkMorning()
        XCTAssertEqual(shown, 1, "already shown today")
        XCTAssertEqual(hidden, 1)
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
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["CS173"])

        model.startMyDay(now: now)
        XCTAssertEqual(model.todayPlan(now: now).priorities.map(\.title), ["CS173"])

        await model.start(priority: tomorrow, subjectID: subject.id, mode: .goal(minutes: 50), now: now)

        XCTAssertEqual(model.todayPlan(now: now).priorities.first?.subjectID, subject.id)
        XCTAssertEqual(harness.engine.subject?.id, subject.id)
    }
}
