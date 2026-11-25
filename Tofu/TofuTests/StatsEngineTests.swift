import XCTest
@testable import Tofu

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
        XCTAssertEqual(StatsSpan.allCases.map(\.title), ["Day", "Week", "Month", "Year"])
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
        XCTAssertEqual(engine.shares(sessions), [SubjectShare(name: "CS128", seconds: 600, fraction: 1,
                                                              sessionCount: 1, average: 600, longest: 600)])
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
        let expected = StatsSummary(today: 0, thisWeek: 0, total: 0, currentStreak: 0, longestStreak: 0, sessionCount: 0,
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

    func testFocusScoreAndDeepWorkCalculation() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 50, outcome: .completed, attempts: 1, tabs: 0),
            session("MATH241", date(2026, 10, 10, 11), minutes: 10, outcome: .completed, attempts: 0, tabs: 0),
        ]
        let summary = engine.summary(sessions)
        // Total = 60m (3600s). Distraction = 1 * 180s. Ratio = 1 - (180/3600) = 0.95 -> 95%
        XCTAssertEqual(summary.focusScore, 95)
        // Deep work (>= 25m): only the 50m session qualifies
        XCTAssertEqual(summary.deepWorkSeconds, 50 * 60)
    }

    func testSummaryAndSharesFollowTheChartRange() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("MATH241", date(2026, 9, 27, 8), minutes: 20),      // first day of the 14
            session("CS128", date(2026, 9, 26, 23), minutes: 50, outcome: .bailed, attempts: 4, tabs: 2),
            session("MATH241", date(2026, 7, 18, 10), minutes: 99),     // before the oldest week
        ]

        let day = engine.summary(sessions, range: .day)
        XCTAssertEqual(day.sessionCount, 2)
        XCTAssertEqual(day.total, 50 * 60)
        XCTAssertEqual(day.today, 30 * 60)
        XCTAssertEqual(day.bails, 0)
        XCTAssertEqual(day.blockedAttempts, 0)
        XCTAssertEqual(day.closedTabs, 0)
        let dayShares = engine.shares(sessions, range: .day)
        XCTAssertEqual(dayShares.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(dayShares.map(\.seconds), [30 * 60, 20 * 60] as [TimeInterval])

        let week = engine.summary(sessions, range: .week)
        XCTAssertEqual(week.sessionCount, 3)
        XCTAssertEqual(week.total, 100 * 60)
        XCTAssertEqual(week.bails, 1)
        XCTAssertEqual(week.blockedAttempts, 4)

        XCTAssertEqual(engine.summary(sessions, range: .month).sessionCount, 4)
        XCTAssertEqual(engine.summary(sessions).sessionCount, 4)
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

    // MARK: - Subject hours

    func testRollingWindowKeepsTheLastSevenDaysAndWeeklyResets() {
        let otherID = UUID()
        let kept = session("CS128", date(2026, 10, 10, 9), minutes: 30)
        var sameSubjectLastWeek = session("CS128", date(2026, 10, 3, 23), minutes: 90)
        sameSubjectLastWeek.subjectID = subjectID
        var otherSubject = session("MATH241", date(2026, 10, 10, 11), minutes: 15)
        otherSubject.subjectID = otherID
        let justInside = session("CS128", date(2026, 10, 3, 15), minutes: 10)
        let justOutside = session("CS128", date(2026, 10, 3, 14), minutes: 40)
        let sunday = session("CS128", date(2026, 10, 4, 0, 30), minutes: 20)
        let sessions = [kept, sameSubjectLastWeek, otherSubject, justInside, justOutside, sunday]

        XCTAssertEqual(SubjectHoursWindow.rolling.caption, "Last 7 days")
        XCTAssertEqual(SubjectHoursWindow.week.caption, "This week")
        XCTAssertEqual(engine.seconds(for: subjectID, in: sessions, window: .rolling), (30 + 90 + 10 + 20) * 60)
        XCTAssertEqual(engine.seconds(for: subjectID, in: sessions, window: .week), (30 + 20) * 60)
        XCTAssertEqual(engine.seconds(for: otherID, in: sessions, window: .week), 15 * 60)
        XCTAssertEqual(engine.matching(sessions, window: .rolling).map(\.start),
                       [date(2026, 10, 10, 9), date(2026, 10, 3, 23), date(2026, 10, 10, 11),
                        date(2026, 10, 3, 15), date(2026, 10, 4, 0, 30)])
        XCTAssertEqual(engine.shares(engine.matching(sessions, window: .week)).map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(engine.shares(engine.matching(sessions, window: .week)).map(\.seconds), [50 * 60, 15 * 60] as [TimeInterval])
    }

    func testAPeriodShowsOnlyThatDayWeekMonthOrYear() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("MATH241", date(2026, 10, 9, 18), minutes: 20),
            session("CS128", date(2026, 10, 3, 10), minutes: 40),      // previous week
            session("MATH241", date(2026, 9, 30, 9), minutes: 15),     // previous month
            session("CS128", date(2026, 1, 15, 9), minutes: 25),
            session("MATH241", date(2025, 11, 1, 9), minutes: 99),     // previous year
        ]

        XCTAssertEqual(engine.heading(.day, containing: now), "Saturday, Oct 10")
        XCTAssertEqual(engine.monthDay(now), "10/10")
        XCTAssertEqual(engine.chipTitle(.day, containing: now), "Oct 10")
        XCTAssertEqual(engine.heading(.week, containing: now), "Oct 4 – Oct 10")
        XCTAssertEqual(engine.heading(.month, containing: now), "October 2026")
        XCTAssertEqual(engine.heading(.year, containing: now), "2026")
        XCTAssertEqual(engine.shift(now, span: .day, by: -1), date(2026, 10, 9, 0))
        XCTAssertEqual(engine.shift(now, span: .week, by: -1), date(2026, 9, 27, 0))

        let day = engine.summary(engine.matching(sessions, span: .day, containing: now))
        XCTAssertEqual(day.sessionCount, 1)
        XCTAssertEqual(day.total, 30 * 60)
        XCTAssertEqual(engine.shares(engine.matching(sessions, span: .day, containing: now)).map(\.name), ["CS128"])

        let week = engine.matching(sessions, span: .week, containing: now)
        XCTAssertEqual(week.map(\.start), [date(2026, 10, 10, 9), date(2026, 10, 9, 18)])
        let weekBars = engine.periodBuckets(sessions, span: .week, containing: now)
        XCTAssertEqual(weekBars.count, 7)
        XCTAssertEqual(weekBars.first?.start, date(2026, 10, 4, 0))
        XCTAssertEqual(weekBars.first?.label, "Oct 4")
        XCTAssertEqual(weekBars.last?.minutesBySubject, ["CS128": 30])
        XCTAssertEqual(weekBars[5].minutesBySubject, ["MATH241": 20])

        let monthBars = engine.periodBuckets(sessions, span: .month, containing: now)
        XCTAssertEqual(monthBars.count, 31)
        XCTAssertEqual(monthBars.first?.label, "1")
        XCTAssertEqual(monthBars.last?.label, "31")
        XCTAssertEqual(monthBars.map(\.totalMinutes).reduce(0, +), 30 + 20 + 40)
        XCTAssertEqual(engine.matching(sessions, span: .month, containing: date(2026, 9, 15, 0)).map(\.start),
                       [date(2026, 9, 30, 9)])

        let yearBars = engine.periodBuckets(sessions, span: .year, containing: now)
        XCTAssertEqual(yearBars.count, 12)
        XCTAssertEqual(yearBars.map(\.label), ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        XCTAssertEqual(yearBars[0].minutesBySubject, ["CS128": 25])
        XCTAssertEqual(yearBars[8].minutesBySubject, ["MATH241": 15])
        XCTAssertEqual(yearBars[9].minutesBySubject, ["CS128": 70, "MATH241": 20])
        XCTAssertEqual(engine.summary(engine.matching(sessions, span: .year, containing: now)).total, (30 + 20 + 40 + 15 + 25) * 60)

        let marks = engine.timeline(sessions, span: .month)
        XCTAssertEqual(marks.first, date(2025, 11, 1, 0))
        XCTAssertEqual(marks.last, date(2026, 10, 1, 0))
        XCTAssertTrue(marks.contains(date(2025, 11, 1, 0)))
        XCTAssertFalse(marks.contains(date(2026, 11, 1, 0)))
    }

    func testAnActiveSessionDoesNotCountTowardSubjectHours() {
        let active = Session(subjectID: subjectID, subjectName: "CS128", mode: .open,
                             start: date(2026, 10, 10, 13), lastHeartbeat: date(2026, 10, 10, 14))
        XCTAssertEqual(engine.seconds(for: subjectID, in: [active], window: .rolling), 0)
        XCTAssertEqual(engine.seconds(for: subjectID, in: [active], window: .week), 0)
    }

    func testHourlyDistributionGroupsByHourOfDay() {
        // Session 1: 9:00 AM, 45 minutes
        let s1 = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 45),
                         start: date(2026, 10, 10, 9, 0), end: date(2026, 10, 10, 9, 45),
                         outcome: .completed)
        // Session 2: 9:30 AM (another block), 30 minutes -> hour 9 has 75 minutes total
        let s2 = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 30),
                         start: date(2026, 10, 9, 9, 30), end: date(2026, 10, 9, 10, 0),
                         outcome: .completed)
        // Session 3: 2:00 PM (hour 14), 60 minutes
        let s3 = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 60),
                         start: date(2026, 10, 10, 14, 0), end: date(2026, 10, 10, 15, 0),
                         outcome: .completed)

        let distribution = engine.hourlyDistribution([s1, s2, s3])
        XCTAssertEqual(distribution.count, 24)

        let hour9 = distribution.first { $0.hour == 9 }!
        XCTAssertEqual(hour9.totalMinutes, 75.0)
        XCTAssertEqual(hour9.sessionCount, 2)
        XCTAssertEqual(hour9.hourLabel, "9 AM")

        let hour14 = distribution.first { $0.hour == 14 }!
        XCTAssertEqual(hour14.totalMinutes, 60.0)
        XCTAssertEqual(hour14.sessionCount, 1)
        XCTAssertEqual(hour14.hourLabel, "2 PM")

        let hour0 = distribution.first { $0.hour == 0 }!
        XCTAssertEqual(hour0.totalMinutes, 0.0)
        XCTAssertEqual(hour0.sessionCount, 0)
    }

    func testFocusVelocityComputesMomentumScore() {
        // High volume, fully completed clean sessions:
        // 2x 60m clean completed sessions = 120 mins -> full 30 volume, full 40 comp, full 30 clean -> 100
        let s1 = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 60),
                         start: date(2026, 10, 10, 9, 0), end: date(2026, 10, 10, 10, 0),
                         blockedAttempts: 0, closedTabs: 0, outcome: .completed)
        let s2 = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 60),
                         start: date(2026, 10, 10, 11, 0), end: date(2026, 10, 10, 12, 0),
                         blockedAttempts: 0, closedTabs: 0, outcome: .completed)

        let vel = engine.focusVelocity([s1, s2])
        XCTAssertEqual(vel.score, 100)
        XCTAssertEqual(vel.rating, "Exceptional")
        XCTAssertEqual(vel.cleanSessionRate, 1.0)
        XCTAssertEqual(vel.completionRate, 1.0)

        // Bailed session with violations scores lower
        let bailed = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 30),
                             start: date(2026, 10, 10, 13, 0), end: date(2026, 10, 10, 13, 10),
                             blockedAttempts: 3, closedTabs: 2, outcome: .bailed)
        let mixedVel = engine.focusVelocity([bailed])
        XCTAssertLessThan(mixedVel.score, 50)
        XCTAssertEqual(mixedVel.rating, "Building")
    }

    func testConsistencyHeatmapBuildsTwelveWeekGridWithIntensityLevels() {
        let light = session("CS128", date(2026, 10, 9, 10, 0), minutes: 30)
        let deep = session("CS128", date(2026, 10, 10, 9, 0), minutes: 300)

        let columns = engine.consistencyHeatmap(sessions: [light, deep], weeks: 12)
        XCTAssertEqual(columns.count, 12)
        XCTAssertTrue(columns.allSatisfy { $0.count == 7 })

        let allDays = columns.flatMap { $0 }
        let oct9 = allDays.first { $0.dayKey == "2026-10-09" }
        let oct10 = allDays.first { $0.dayKey == "2026-10-10" }
        XCTAssertEqual(oct9?.intensityLevel, 1)
        XCTAssertEqual(oct9?.sessionCount, 1)
        XCTAssertEqual(oct10?.intensityLevel, 4)
        XCTAssertEqual(oct10?.totalMinutes, 300)
    }

    func testPeriodComparisonComputesDeltaAgainstPreviousSpan() {
        let yesterday = session("CS128", date(2026, 10, 9, 10, 0), minutes: 60)
        let today = session("CS128", date(2026, 10, 10, 9, 0), minutes: 120)

        let cmp = engine.periodComparison([yesterday, today], span: .day, containing: now)
        XCTAssertEqual(cmp.currentTotal, 7200)
        XCTAssertEqual(cmp.previousTotal, 3600)
        XCTAssertEqual(cmp.deltaSeconds, 3600)
        XCTAssertEqual(cmp.deltaPercent, 100)
        XCTAssertTrue(cmp.trendLabel.contains("+1h"))
        XCTAssertTrue(cmp.trendLabel.contains("+100%"))
    }

    func testTimeOfDayBreakdownBucketsMorningAfternoonEveningNight() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 45),
            session("CS128", date(2026, 10, 10, 14), minutes: 60),
            session("CS128", date(2026, 10, 10, 20), minutes: 30),
            session("CS128", date(2026, 10, 10, 1), minutes: 15),
        ]

        let parts = engine.timeOfDayBreakdown(sessions)
        XCTAssertEqual(parts.map(\.label), ["Morning", "Afternoon", "Evening", "Night"])
        XCTAssertEqual(parts[0].minutes, 45, accuracy: 0.01)
        XCTAssertEqual(parts[1].minutes, 60, accuracy: 0.01)
        XCTAssertEqual(parts[2].minutes, 30, accuracy: 0.01)
        XCTAssertEqual(parts[3].minutes, 15, accuracy: 0.01)
    }
}
