import XCTest
@testable import Tofu

final class FocusMomentumTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testCompute7DayMomentumWithNoSessions() {
        let today = makeDate(year: 2026, month: 11, day: 24, hour: 12)
        let summary = FocusMomentumEngine.compute7DayMomentum(sessions: [], today: today, calendar: calendar)

        XCTAssertEqual(summary.slices.count, 7)
        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.totalWeekSeconds, 0)
        XCTAssertEqual(summary.bestDaySeconds, 0)

        // The last slice should be today
        XCTAssertTrue(summary.slices.last?.isToday == true)
        XCTAssertEqual(summary.slices.last?.dayKey, DayKey.key(for: today, calendar: calendar))

        // All slices have 0 seconds
        for slice in summary.slices {
            XCTAssertEqual(slice.focusSeconds, 0)
            XCTAssertEqual(slice.sessionCount, 0)
        }
    }

    func testCompute7DayMomentumAggregatesDailySessions() {
        let today = makeDate(year: 2026, month: 11, day: 24, hour: 12)
        let subID = UUID()

        // Session today: 50m (3000s)
        let s1 = Session(id: UUID(), subjectID: subID, subjectName: "Math", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 24, hour: 9),
                         end: makeDate(year: 2026, month: 11, day: 24, hour: 9, minute: 50),
                         outcome: .completed)

        // Another session today: 25m (1500s)
        let s2 = Session(id: UUID(), subjectID: subID, subjectName: "Math", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 24, hour: 10),
                         end: makeDate(year: 2026, month: 11, day: 24, hour: 10, minute: 25),
                         outcome: .completed)

        // Session yesterday (Nov 23): 60m (3600s)
        let s3 = Session(id: UUID(), subjectID: subID, subjectName: "Physics", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 23, hour: 14),
                         end: makeDate(year: 2026, month: 11, day: 23, hour: 15),
                         outcome: .completed)

        // Session 3 days ago (Nov 21): 40m (2400s)
        let s4 = Session(id: UUID(), subjectID: subID, subjectName: "Physics", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 21, hour: 11),
                         end: makeDate(year: 2026, month: 11, day: 21, hour: 11, minute: 40),
                         outcome: .completed)

        // Session 10 days ago (outside 7-day window): 120m (7200s)
        let sOld = Session(id: UUID(), subjectID: subID, subjectName: "Physics", mode: .open,
                           start: makeDate(year: 2026, month: 11, day: 14, hour: 11),
                           end: makeDate(year: 2026, month: 11, day: 14, hour: 13),
                           outcome: .completed)

        let sessions = [s1, s2, s3, s4, sOld]
        let summary = FocusMomentumEngine.compute7DayMomentum(sessions: sessions, today: today, calendar: calendar)

        XCTAssertEqual(summary.slices.count, 7)
        // Today total = 3000 + 1500 = 4500s
        XCTAssertEqual(summary.slices.last?.focusSeconds, 4500)
        XCTAssertEqual(summary.slices.last?.sessionCount, 2)

        // Total 7-day = 4500 + 3600 + 2400 = 10500s
        XCTAssertEqual(summary.totalWeekSeconds, 10500)
        XCTAssertEqual(summary.bestDaySeconds, 4500)

        // Day labels: single letter day of week (e.g. "T" for Tuesday)
        XCTAssertFalse(summary.slices.last!.dayLabel.isEmpty)
    }

    func testComputeStreakContinuity() {
        let today = makeDate(year: 2026, month: 11, day: 24, hour: 12)
        let subID = UUID()

        // 3 consecutive days: Nov 22, Nov 23, Nov 24
        let s1 = Session(id: UUID(), subjectID: subID, subjectName: "Code", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 24, hour: 9),
                         end: makeDate(year: 2026, month: 11, day: 24, hour: 10),
                         outcome: .completed)

        let s2 = Session(id: UUID(), subjectID: subID, subjectName: "Code", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 23, hour: 9),
                         end: makeDate(year: 2026, month: 11, day: 23, hour: 10),
                         outcome: .completed)

        let s3 = Session(id: UUID(), subjectID: subID, subjectName: "Code", mode: .open,
                         start: makeDate(year: 2026, month: 11, day: 22, hour: 9),
                         end: makeDate(year: 2026, month: 11, day: 22, hour: 10),
                         outcome: .completed)

        let summary = FocusMomentumEngine.compute7DayMomentum(sessions: [s1, s2, s3], today: today, calendar: calendar)
        XCTAssertEqual(summary.currentStreak, 3)
    }

    func testActiveAndDemoSessionsIgnored() {
        let today = makeDate(year: 2026, month: 11, day: 24, hour: 12)
        let subID = UUID()

        // Demo session
        let sDemo = Session(id: UUID(), subjectID: subID, subjectName: "Demo", mode: .open,
                            start: today, end: today.addingTimeInterval(1800),
                            outcome: .completed, isDemo: true)

        // Unfinished session (end == nil)
        let sUnfinished = Session(id: UUID(), subjectID: subID, subjectName: "Work", mode: .open,
                                  start: today, end: nil, outcome: nil)

        let summary = FocusMomentumEngine.compute7DayMomentum(sessions: [sDemo, sUnfinished], today: today, calendar: calendar)
        XCTAssertEqual(summary.totalWeekSeconds, 0)
        XCTAssertEqual(summary.currentStreak, 0)
    }
}
