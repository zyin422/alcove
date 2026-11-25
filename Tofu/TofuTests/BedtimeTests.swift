import XCTest
@testable import Tofu

@MainActor
final class BedtimeTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func makeStore() throws -> Store {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BedtimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Store(fileURL: directory.appendingPathComponent("store.json"))
    }

    func testIsPastMidnightWindow() {
        XCTAssertTrue(DayPlanner.isPastMidnight(now: date(10, 0, 0), calendar: calendar))
        XCTAssertTrue(DayPlanner.isPastMidnight(now: date(10, 1, 30), calendar: calendar))
        XCTAssertTrue(DayPlanner.isPastMidnight(now: date(10, 3, 59), calendar: calendar))

        XCTAssertFalse(DayPlanner.isPastMidnight(now: date(10, 4, 0), calendar: calendar))
        XCTAssertFalse(DayPlanner.isPastMidnight(now: date(10, 12, 0), calendar: calendar))
        XCTAssertFalse(DayPlanner.isPastMidnight(now: date(10, 23, 59), calendar: calendar))
    }

    func testBedtimeSecondsRemaining() {
        // At 00:00: exactly 4 hours (14,400s) until 04:00
        XCTAssertEqual(DayPlanner.bedtimeSecondsRemaining(now: date(10, 0, 0), calendar: calendar), 14400)

        // At 01:30: exactly 2.5 hours (9,000s) until 04:00
        XCTAssertEqual(DayPlanner.bedtimeSecondsRemaining(now: date(10, 1, 30), calendar: calendar), 9000)

        // At 03:59: exactly 60 seconds until 04:00
        XCTAssertEqual(DayPlanner.bedtimeSecondsRemaining(now: date(10, 3, 59), calendar: calendar), 60)

        // At 04:00: guard lifts, returns 0
        XCTAssertEqual(DayPlanner.bedtimeSecondsRemaining(now: date(10, 4, 0), calendar: calendar), 0)

        // During daytime: returns 0
        XCTAssertEqual(DayPlanner.bedtimeSecondsRemaining(now: date(10, 15, 0), calendar: calendar), 0)
    }

    func testShouldShowBedtimeGuard() {
        var settings = AppSettings()
        settings.bedtimeGuardEnabled = true

        // Past midnight and not locked: should show
        XCTAssertTrue(DayPlanner.shouldShowBedtime(now: date(10, 1, 0), settings: settings, isLocked: false, calendar: calendar))

        // Past midnight but locked in an active block: should NOT interrupt block
        XCTAssertFalse(DayPlanner.shouldShowBedtime(now: date(10, 1, 0), settings: settings, isLocked: true, calendar: calendar))

        // Daytime: should NOT show
        XCTAssertFalse(DayPlanner.shouldShowBedtime(now: date(10, 14, 0), settings: settings, isLocked: false, calendar: calendar))

        // Feature disabled
        settings.bedtimeGuardEnabled = false
        XCTAssertFalse(DayPlanner.shouldShowBedtime(now: date(10, 1, 0), settings: settings, isLocked: false, calendar: calendar))
    }

    func testBedtimeFramesCoverDisplays() {
        let screen1 = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let screen2 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(BedtimeWindowPolicy.frames(covering: [screen1, screen2, .zero]), [screen1, screen2])
    }

    func testMidnightPlanningIsSingleUsePerNight() async throws {
        let h = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: h.engine)

        let midnightTime = date(10, 1, 30)
        XCTAssertTrue(model.canPlanTonight(now: midnightTime))

        var bedtimeHidden = false
        model.onHideBedtime = { bedtimeHidden = true }
        model.isShowingBedtime = true

        await model.startPlanningFromBedtime(now: midnightTime)

        XCTAssertTrue(bedtimeHidden)
        XCTAssertFalse(model.isShowingBedtime)
        XCTAssertEqual(model.data.settings.lastMidnightPlanningKey, DayKey.key(for: midnightTime))
        XCTAssertFalse(model.canPlanTonight(now: midnightTime))
        XCTAssertTrue(h.engine.isLocked)
        XCTAssertEqual(h.engine.session?.subjectName, "Planning Mode")
    }

    func testNextMidnightBedtimeReturnsWindDownCountdownOnlyInHour23() {
        var settings = AppSettings(bedtimeGuardEnabled: true)
        let preWindow = date(10, 22, 30)
        XCTAssertNil(DayPlanner.nextMidnightBedtime(after: preWindow, bedtimeGuardEnabled: settings.bedtimeGuardEnabled, calendar: calendar))

        let at2345 = date(10, 23, 45)
        let countdown = DayPlanner.secondsUntilMidnightBedtime(now: at2345, bedtimeGuardEnabled: settings.bedtimeGuardEnabled, calendar: calendar)
        XCTAssertEqual(countdown ?? -1, 15 * 60, accuracy: 0.5)

        settings.bedtimeGuardEnabled = false
        XCTAssertNil(DayPlanner.nextMidnightBedtime(after: at2345, bedtimeGuardEnabled: settings.bedtimeGuardEnabled, calendar: calendar))
    }
}
