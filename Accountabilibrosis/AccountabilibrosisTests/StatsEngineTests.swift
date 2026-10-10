import XCTest
@testable import Accountabilibrosis

final class StatsEngineTests: XCTestCase {
    /// Gregorian, UTC, en_US_POSIX, weeks start on Sunday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()
    private let subjectID = UUID()

    /// Saturday 2026-10-10 15:00 UTC. This week starts Sunday 2026-10-04.
    private var now: Date { date(2026, 10, 10, 15) }
    private var engine: StatsEngine { StatsEngine(calendar: calendar, now: now) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { fatalError("invalid test date") }
        return date
    }

    /// Ended session of `minutes` length (end == lastHeartbeat).
    private func session(_ name: String, _ start: Date, minutes: Double, outcome: SessionOutcome = .completed,
                         attempts: Int = 0, tabs: Int = 0) -> Session {
        let end = start.addingTimeInterval(minutes * 60)
        return Session(subjectID: subjectID, subjectName: name, mode: .open, start: start, end: end,
                       lastHeartbeat: end, blockedAttempts: attempts, closedTabs: tabs, outcome: outcome)
    }

    // MARK: - Ranges

    func testRangeTitles() {
        XCTAssertEqual(StatsRange.allCases.map(\.title), ["Day", "Week", "Month"])
    }

    // MARK: - Buckets

    func testDayBucketsCoverFourteenDaysEndingToday() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("CS128", date(2026, 10, 10, 13), minutes: 15),
            session("MATH241", date(2026, 10, 9, 20), minutes: 60),
            session("CS128", date(2026, 9, 27, 8), minutes: 20),
            session("CS128", date(2026, 9, 26, 23), minutes: 50),   // 14 days ago: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .day)

        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(buckets.first?.start, date(2026, 9, 27, 0))
        XCTAssertEqual(buckets.first?.label, "Sep 27")
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 10, 0))
        XCTAssertEqual(buckets.last?.label, "Oct 10")
        for (earlier, later) in zip(buckets, buckets.dropFirst()) {
            XCTAssertEqual(later.start.timeIntervalSince(earlier.start), 86_400)
        }
        XCTAssertEqual(buckets[13].minutesBySubject, ["CS128": 45])
        XCTAssertEqual(buckets[12].minutesBySubject, ["MATH241": 60])
        XCTAssertEqual(buckets[1].minutesBySubject, [:])
        XCTAssertEqual(buckets[0].minutesBySubject, ["CS128": 20])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 125)
    }

    func testSessionSpanningMidnightCountsOnItsStartDay() {
        let sessions = [session("CS128", date(2026, 10, 9, 23, 30), minutes: 60)]
        let buckets = engine.buckets(sessions, range: .day)

        XCTAssertEqual(buckets[12].minutesBySubject, ["CS128": 60])
        XCTAssertEqual(buckets[13].minutesBySubject, [:])
        XCTAssertEqual(engine.summary(sessions).today, 0)
    }

    func testWeekBucketsAreTwelveCalendarWeeksEndingThisWeek() {
        let sessions = [
            session("CS128", date(2026, 10, 4, 10), minutes: 40),    // Sunday: first day of this week
            session("CS128", date(2026, 10, 3, 10), minutes: 25),    // Saturday: previous week
            session("MATH241", date(2026, 7, 19, 10), minutes: 10),  // Sunday of the oldest week
            session("MATH241", date(2026, 7, 18, 10), minutes: 99),  // 12 weeks back: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .week)

        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 4, 0))
        XCTAssertEqual(buckets.last?.label, "Oct 4")
        XCTAssertEqual(buckets.first?.start, date(2026, 7, 19, 0))
        XCTAssertEqual(buckets.first?.label, "Jul 19")
        XCTAssertEqual(buckets[11].minutesBySubject, ["CS128": 40])
        XCTAssertEqual(buckets[10].minutesBySubject, ["CS128": 25])
        XCTAssertEqual(buckets[0].minutesBySubject, ["MATH241": 10])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 75)
    }

    func testMonthBucketsAreTwelveMonthsEndingThisMonth() {
        let sessions = [
            session("CS128", date(2026, 10, 1, 9), minutes: 30),
            session("CS128", date(2026, 9, 30, 9), minutes: 45),
            session("MATH241", date(2025, 11, 15, 9), minutes: 20),
            session("MATH241", date(2025, 10, 31, 9), minutes: 99),  // 12 months back: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .month)

        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 1, 0))
        XCTAssertEqual(buckets.last?.label, "Oct")
        XCTAssertEqual(buckets.first?.start, date(2025, 11, 1, 0))
        XCTAssertEqual(buckets.first?.label, "Nov")
        XCTAssertEqual(buckets[11].minutesBySubject, ["CS128": 30])
        XCTAssertEqual(buckets[10].minutesBySubject, ["CS128": 45])
        XCTAssertEqual(buckets[0].minutesBySubject, ["MATH241": 20])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 95)
    }

    func testActiveSessionIsIgnoredEverywhere() {
        let active = Session(subjectID: subjectID, subjectName: "CS128", mode: .open,
                             start: date(2026, 10, 10, 13), lastHeartbeat: date(2026, 10, 10, 14))
        let finished = session("CS128", date(2026, 10, 10, 9), minutes: 10)
        let sessions = [active, finished]

        XCTAssertEqual(engine.buckets(sessions, range: .day).last?.minutesBySubject, ["CS128": 10])
        let summary = engine.summary(sessions)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.today, 600)
        XCTAssertEqual(engine.shares(sessions), [SubjectShare(name: "CS128", seconds: 600, fraction: 1)])
    }

    func testSubjectsOutsideTopNAreMergedIntoOther() {
        let sessions = [
            session("A", date(2026, 10, 10, 8), minutes: 100),
            session("B", date(2026, 10, 10, 10), minutes: 80),
            session("C", date(2026, 10, 10, 12), minutes: 60),
            session("D", date(2026, 10, 10, 14), minutes: 30),
            session("D", date(2026, 10, 1, 9), minutes: 200),   // makes D the biggest subject overall
        ]
        let top2 = engine.buckets(sessions, range: .day, topSubjects: 2)
        XCTAssertEqual(top2[13].minutesBySubject, ["D": 30, "A": 100, StatsEngine.otherLabel: 140])
        XCTAssertEqual(top2[4].minutesBySubject, ["D": 200])

        let defaultTop = engine.buckets(sessions, range: .day)
        XCTAssertEqual(defaultTop[13].minutesBySubject, ["A": 100, "B": 80, "C": 60, "D": 30])
    }

    // MARK: - Summary

    func testSummaryTodayAndThisWeek() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("MATH241", date(2026, 10, 10, 11), minutes: 15),
            session("CS128", date(2026, 10, 5, 9), minutes: 60),      // Monday of this week
            session("CS128", date(2026, 10, 4, 0, 30), minutes: 20),  // Sunday, first day of this week
            session("CS128", date(2026, 10, 3, 23), minutes: 90),     // Saturday of last week
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.today, 45 * 60)
        XCTAssertEqual(summary.thisWeek, 125 * 60)
        XCTAssertEqual(summary.sessionCount, 5)
    }

    func testCurrentStreakIncludesTodayWhenTodayQualifies() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 10),
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 6, 9), minutes: 10),   // Oct 7 is missing
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.longestStreak, 3)
    }

    func testCurrentStreakCountsFromYesterdayWhenTodayIsUnderFiveMinutes() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 4),    // today: below the threshold
            session("CS128", date(2026, 10, 9, 9), minutes: 30),
            session("CS128", date(2026, 10, 8, 9), minutes: 30),
            session("CS128", date(2026, 10, 7, 9), minutes: 3),     // two short sessions add up to 6 min
            session("MATH241", date(2026, 10, 7, 18), minutes: 3),
        ]

        XCTAssertEqual(engine.summary(sessions).currentStreak, 3)
    }

    func testExactlyFiveMinutesQualifies() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 5),
            session("CS128", date(2026, 10, 9, 9), minutes: 5),
        ]

        XCTAssertEqual(engine.summary(sessions).currentStreak, 2)
    }

    func testGapBreaksCurrentStreak() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
            session("CS128", date(2026, 10, 8, 9), minutes: 10),   // Oct 9 is missing
            session("CS128", date(2026, 10, 7, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 1)
        XCTAssertEqual(summary.longestStreak, 2)
    }

    func testNoCurrentStreakWhenTodayAndYesterdayAreEmpty() {
        let sessions = [
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 7, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.longestStreak, 2)
    }

    func testLongestStreakFindsLongestRunOfQualifyingDays() {
        var sessions = (1...5).map { session("CS128", date(2026, 9, $0, 9), minutes: 10) }   // Sep 1-5
        sessions += [
            session("CS128", date(2026, 9, 20, 9), minutes: 10),
            session("CS128", date(2026, 9, 21, 9), minutes: 4),    // too short: breaks Sep 20-22
            session("CS128", date(2026, 9, 22, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 10),
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.longestStreak, 5)
        XCTAssertEqual(summary.currentStreak, 2)
    }

    func testAverageAndLongestSession() {
        let sessions = [
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 20),
            session("MATH241", date(2026, 10, 10, 9), minutes: 60),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(summary.average, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.longest, 60 * 60)
    }

    func testEmptySummaryIsAllZero() {
        let expected = StatsSummary(today: 0, thisWeek: 0, currentStreak: 0, longestStreak: 0, sessionCount: 0,
                                    average: 0, longest: 0, blockedAttempts: 0, closedTabs: 0, bails: 0)
        XCTAssertEqual(engine.summary([]), expected)
    }

    func testBailsAttemptsAndClosedTabsAreTotalled() {
        let sessions = [
            session("CS128", date(2026, 10, 7, 9), minutes: 10, outcome: .completed, attempts: 1, tabs: 0),
            session("CS128", date(2026, 10, 8, 9), minutes: 10, outcome: .bailed, attempts: 2, tabs: 1),
            session("CS128", date(2026, 10, 9, 9), minutes: 10, outcome: .bailed, attempts: 3, tabs: 4),
            session("CS128", date(2026, 10, 10, 9), minutes: 10, outcome: .interrupted, attempts: 0, tabs: 2),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.bails, 2)
        XCTAssertEqual(summary.blockedAttempts, 6)
        XCTAssertEqual(summary.closedTabs, 7)
    }

    func testInterruptedSessionCountsUpToItsLastHeartbeat() {
        let start = date(2026, 10, 10, 9)
        let heartbeat = date(2026, 10, 10, 9, 40)
        // Store.finalizeInterrupted sets end = lastHeartbeat after a crash.
        let interrupted = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 50),
                                  start: start, end: heartbeat, lastHeartbeat: heartbeat, outcome: .interrupted)
        let summary = engine.summary([interrupted])

        XCTAssertEqual(summary.today, 40 * 60)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.bails, 0)
        XCTAssertEqual(engine.buckets([interrupted], range: .day).last?.minutesBySubject, ["CS128": 40])
    }

    // MARK: - Shares

    func testSharesAreSortedDescendingAndSumToOne() {
        let active = Session(subjectID: subjectID, subjectName: "D", mode: .open,
                             start: date(2026, 10, 10, 13), lastHeartbeat: date(2026, 10, 10, 14))
        let sessions = [
            session("A", date(2026, 10, 8, 9), minutes: 30),
            session("B", date(2026, 10, 9, 9), minutes: 90),
            session("C", date(2026, 10, 10, 9), minutes: 60),
            active,
        ]
        let shares = engine.shares(sessions)

        XCTAssertEqual(shares.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(shares.map(\.seconds), [5400, 3600, 1800])
        XCTAssertEqual(shares[0].fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shares[1].fraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(shares[2].fraction, 1.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testSharesTieBreakByNameAndEmptyInput() {
        let sessions = [
            session("Zeta", date(2026, 10, 9, 9), minutes: 10),
            session("Alpha", date(2026, 10, 10, 9), minutes: 10),
        ]

        XCTAssertEqual(engine.shares(sessions).map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(engine.shares([]), [])
    }
}
