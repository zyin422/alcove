import XCTest
@testable import Tofu

final class StatsFormattingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func bucket(_ dayOffset: Int, _ minutes: [String: Double]) -> StatsBucket {
        let day = start.addingTimeInterval(TimeInterval(dayOffset) * 86_400)
        return StatsBucket(start: day, label: "D\(dayOffset)", minutesBySubject: minutes)
    }

    /// `minutes` long; ended unless `active`.
    private func session(_ name: String, minutes: Double, active: Bool = false) -> Session {
        let end = start.addingTimeInterval(minutes * 60)
        return Session(subjectID: UUID(), subjectName: name, mode: .open, start: start,
                       end: active ? nil : end, lastHeartbeat: end)
    }

    // MARK: - Labels

    func testStreakLabel() {
        XCTAssertEqual(StatsFormatting.streak(0), "0 days")
        XCTAssertEqual(StatsFormatting.streak(1), "1 day")
        XCTAssertEqual(StatsFormatting.streak(2), "2 days")
        XCTAssertEqual(StatsFormatting.streak(30), "30 days")
    }

    func testPercentIsRoundedToWholeNumbers() {
        XCTAssertEqual(StatsFormatting.percent(0.42), "42%")
        XCTAssertEqual(StatsFormatting.percent(0.4249), "42%")
        XCTAssertEqual(StatsFormatting.percent(0.426), "43%")
        XCTAssertEqual(StatsFormatting.percent(1.0 / 3.0), "33%")
        XCTAssertEqual(StatsFormatting.percent(0.004), "0%")
        XCTAssertEqual(StatsFormatting.percent(0), "0%")
        XCTAssertEqual(StatsFormatting.percent(1), "100%")
    }

    func testPercentAndBarFractionAreClamped() {
        XCTAssertEqual(StatsFormatting.percent(-0.2), "0%")
        XCTAssertEqual(StatsFormatting.percent(1.7), "100%")
        XCTAssertEqual(StatsFormatting.percent(.nan), "0%")
        XCTAssertEqual(StatsFormatting.clampedFraction(0.25), 0.25)
        XCTAssertEqual(StatsFormatting.clampedFraction(-1), 0)
        XCTAssertEqual(StatsFormatting.clampedFraction(2), 1)
        XCTAssertEqual(StatsFormatting.clampedFraction(.infinity), 0)
        XCTAssertEqual(StatsFormatting.clampedFraction(.nan), 0)
    }

    func testRangeCaptions() {
        XCTAssertEqual(StatsRange.allCases.map(StatsFormatting.rangeCaption),
                       ["Last 14 days", "Last 12 weeks", "Last 12 months"])
    }

    func testEmptyMessage() {
        XCTAssertEqual(StatsFormatting.emptyMessage, "No sessions yet — lock in to start tracking.")
    }

    // MARK: - Chart series

    func testChartSubjectsAreOrderedByTotalWithOtherLast() {
        let buckets = [
            bucket(0, ["A": 10, "B": 30]),
            bucket(1, ["B": 5, StatsEngine.otherLabel: 100, "C": 30]),
            bucket(2, [:]),
        ]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["B", "C", "A", StatsEngine.otherLabel])
    }

    func testChartSubjectsBreakTiesByName() {
        let buckets = [bucket(0, ["Zeta": 5, "Alpha": 5]), bucket(1, ["Mid": 5])]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["Alpha", "Mid", "Zeta"])
    }

    func testChartSubjectsDropSeriesWithoutMinutes() {
        let buckets = [bucket(0, ["A": 0, StatsEngine.otherLabel: 0]), bucket(1, ["B": 12])]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["B"])
        XCTAssertEqual(StatsFormatting.chartSubjects([]), [])
    }

    func testAxisLabelsThinOutButKeepTheNewestLabel() {
        let days = (1...14).map { "D\($0)" }
        XCTAssertEqual(StatsFormatting.axisLabels(days, maxCount: 7), ["D2", "D4", "D6", "D8", "D10", "D12", "D14"])
        let months = (1...12).map { "M\($0)" }
        XCTAssertEqual(StatsFormatting.axisLabels(months, maxCount: 7), ["M2", "M4", "M6", "M8", "M10", "M12"])
        XCTAssertEqual(StatsFormatting.axisLabels(months, maxCount: 4), ["M3", "M6", "M9", "M12"])
        XCTAssertEqual(StatsFormatting.axisLabels(["A", "B", "C"], maxCount: 7), ["A", "B", "C"])
        XCTAssertEqual(StatsFormatting.axisLabels(days, maxCount: 0), [])
        XCTAssertEqual(StatsFormatting.axisLabels([], maxCount: 7), [])
    }

    func testMaxAxisLabelsPerRange() {
        XCTAssertEqual(StatsRange.allCases.map(StatsFormatting.maxAxisLabels), [7, 6, 12])
    }

    func testTopSubjectLimitKeepsEverySeriesWithinTheShades() {
        let five = ["A", "B", "C", "D", "E"].map { session($0, minutes: 10) }
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: [], shades: 5), 5)
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: five, shades: 5), 5)
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: five + [session("F", minutes: 1)], shades: 5), 4)
        // Same name twice and an active session do not count as extra subjects.
        let repeated = five + [session("A", minutes: 3), session("G", minutes: 3, active: true)]
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: repeated, shades: 5), 5)
    }

    // MARK: - Session helpers

    func testTrackedSessionsAndTotalIgnoreActiveSessions() {
        let active = session("CS128", minutes: 50, active: true)
        XCTAssertFalse(StatsFormatting.hasTrackedSessions([]))
        XCTAssertFalse(StatsFormatting.hasTrackedSessions([active]))
        XCTAssertEqual(StatsFormatting.totalSeconds([active]), 0)

        let sessions = [active, session("CS128", minutes: 30), session("MATH241", minutes: 15)]
        XCTAssertTrue(StatsFormatting.hasTrackedSessions(sessions))
        XCTAssertEqual(StatsFormatting.totalSeconds(sessions), 45 * 60, accuracy: 0.001)
    }

    func testSubjectBlocksGroupAPeriodOldestFirstInsideEachSubject() {
        let later = Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                            start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400), outcome: .completed)
        let earlier = Session(subjectID: UUID(), subjectName: "CS128", mode: .open,
                              start: start, end: start.addingTimeInterval(600), outcome: .completed)
        let other = Session(subjectID: UUID(), subjectName: "MATH241", mode: .open,
                            start: start.addingTimeInterval(7200), end: start.addingTimeInterval(9000), outcome: .completed)
        let live = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: start, lastHeartbeat: start)
        let grouped = StatsFormatting.subjectBlocks([later, other, earlier, live])

        XCTAssertEqual(grouped.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(grouped[0].seconds, 2400)
        XCTAssertEqual(grouped[0].sessionCount, 2)
        XCTAssertEqual(grouped[0].average, 1200)
        XCTAssertEqual(grouped[0].longest, 1800)
        XCTAssertEqual(grouped[0].blocks.map(\.seconds), [600, 1800])
        XCTAssertEqual(StatsFormatting.subjectLine(sessions: 1, average: 600, longest: 600),
                       "1 session · avg 10m · longest 10m")
        XCTAssertEqual(StatsFormatting.subjectLine(sessions: 2, average: 1200, longest: 1800),
                       "2 sessions · avg 20m · longest 30m")
        XCTAssertEqual(grouped[0].fraction, 2400.0 / 4200.0, accuracy: 1e-9)
        XCTAssertEqual(grouped[1].blocks.map(\.seconds), [1800])
    }

    func testTimeBlocksAreNewestFirstAndSkipALiveBlock() {
        let older = Session(subjectID: UUID(), subjectName: "MATH241", mode: .open, start: start,
                            end: start.addingTimeInterval(600), outcome: .completed)
        let newerStart = start.addingTimeInterval(3600)
        let newer = Session(subjectID: UUID(), subjectName: "CS173", mode: .open, start: newerStart,
                            end: newerStart.addingTimeInterval(1800), outcome: .completed)
        let live = Session(subjectID: UUID(), subjectName: "Research", mode: .open,
                           start: start.addingTimeInterval(8000))

        let blocks = StatsFormatting.timeBlocks([older, live, newer])

        XCTAssertEqual(blocks.map(\.id), [newer.id, older.id])
        XCTAssertEqual(blocks.map(\.subjectName), ["CS173", "MATH241"])
        XCTAssertEqual(blocks[0].seconds, 1800)
        XCTAssertEqual(blocks[1].seconds, 600)
    }

    func testStatCardProperties() {
        let card = StatCard(title: "Score", value: "95%", tint: Theme.emerald, icon: "chart.line.uptrend.xyaxis")
        XCTAssertEqual(card.title, "Score")
        XCTAssertEqual(card.value, "95%")
        XCTAssertEqual(card.tint, Theme.emerald)
        XCTAssertEqual(card.icon, "chart.line.uptrend.xyaxis")
    }

    func testStatsMarkdownRecapIncludesTrendAndSubjectBreakdown() {
        let summary = StatsSummary(total: 7200, currentStreak: 3, longestStreak: 5, sessionCount: 2,
                                   blockedAttempts: 1, closedTabs: 2, bails: 0, focusScore: 88, deepWorkSeconds: 5400)
        let shares = [
            SubjectShare(name: "CS128", seconds: 5400, fraction: 0.75, sessionCount: 1, average: 5400, longest: 5400),
            SubjectShare(name: "Research", seconds: 1800, fraction: 0.25, sessionCount: 1, average: 1800, longest: 1800)
        ]
        let cmp = PeriodComparison(currentTotal: 7200, previousTotal: 3600, deltaSeconds: 3600,
                                   deltaPercent: 100, trendLabel: "+1h (+100%) vs prev week")

        let md = StatsFormatting.markdownRecap(summary: summary, shares: shares, comparison: cmp, span: .week, heading: "Oct 4 – Oct 10")
        XCTAssertTrue(md.contains("### Tofu Focus Recap — Oct 4 – Oct 10 (Week)"))
        XCTAssertTrue(md.contains("+1h (+100%) vs prev week"))
        XCTAssertTrue(md.contains("**CS128:** 1h 30m (75%)"))
        XCTAssertTrue(md.contains("**Research:** 30m (25%)"))
    }
}
