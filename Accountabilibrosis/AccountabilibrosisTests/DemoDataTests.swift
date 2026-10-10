import XCTest
@testable import Accountabilibrosis

final class DemoDataTests: XCTestCase {
    /// Gregorian, UTC, en_US_POSIX, weeks start on Sunday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { fatalError("invalid test date") }
        return date
    }

    /// Saturday 2026-10-10 15:00 UTC.
    private var now: Date { date(2026, 10, 10, 15) }

    func testDefaultSubjects() {
        let subjects = DemoData.defaultSubjects(now: now)
        guard subjects.count == 2 else { return XCTFail("expected 2 subjects, got \(subjects.count)") }

        XCTAssertEqual(subjects.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(subjects.map(\.preset), [.split, .mainSide])
        XCTAssertEqual(subjects[0].sites, ["https://cs128.org", "https://prairielearn.org"])
        XCTAssertEqual(subjects[0].extraDomains, ["piazza.com"])
        XCTAssertEqual(subjects[1].sites, ["https://www.desmos.com/calculator"])
        XCTAssertEqual(subjects[1].extraDomains, [])
        XCTAssertNotEqual(subjects[0].id, subjects[1].id)
        for subject in subjects {
            XCTAssertEqual(subject.sites.count, subject.preset.siteCount)
            XCTAssertEqual(subject.createdAt, now)
            XCTAssertTrue(subject.allowedApps.isEmpty)
        }
    }

    func testGenerateIsDeterministicForTheSameSeed() {
        let subjects = DemoData.defaultSubjects(now: now)
        let first = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 7)
        let second = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 7)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)).count, first.count, "ids must be unique")
    }

    func testDifferentSeedsGiveDifferentSessions() {
        let subjects = DemoData.defaultSubjects(now: now)
        let one = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 1)
        let two = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 2)

        XCTAssertNotEqual(one.map(\.start), two.map(\.start))
    }

    func testSessionsAreEndedDemoSessionsWithinTheLastThirtyDays() {
        let subjects = DemoData.defaultSubjects(now: now)
        let sessions = DemoData.generate(subjects: subjects, days: 30, now: now, calendar: calendar)
        let earliest = now.addingTimeInterval(-30 * 86_400)

        XCTAssertGreaterThan(sessions.count, 10)
        XCTAssertEqual(sessions.map(\.start), sessions.map(\.start).sorted(), "oldest first")
        for session in sessions {
            XCTAssertTrue(session.isDemo)
            guard let end = session.end else {
                XCTFail("demo session without end")
                continue
            }
            XCTAssertLessThanOrEqual(end, now)
            XCTAssertGreaterThanOrEqual(session.start, earliest)
            XCTAssertEqual(session.lastHeartbeat, end)
            XCTAssertGreaterThanOrEqual(session.duration, 15 * 60)
            XCTAssertLessThanOrEqual(session.duration, 120 * 60)
            XCTAssertTrue((8...22).contains(calendar.component(.hour, from: session.start)))
            XCTAssertTrue((0...6).contains(session.blockedAttempts))
            XCTAssertTrue((0...4).contains(session.closedTabs))
        }
    }

    func testOutcomesAreMostlyCompletedAndBailsOnlyHappenInGoalMode() {
        let subjects = DemoData.defaultSubjects(now: now)
        let sessions = DemoData.generate(subjects: subjects, days: 90, now: now, calendar: calendar)
        let bails = sessions.filter { $0.outcome == .bailed }
        let goals = sessions.filter { $0.mode.goalMinutes != nil }

        XCTAssertTrue(sessions.allSatisfy { $0.outcome == .completed || $0.outcome == .bailed })
        XCTAssertGreaterThan(bails.count, 0)
        XCTAssertLessThan(Double(bails.count) / Double(sessions.count), 0.25)
        XCTAssertGreaterThan(Double(goals.count) / Double(sessions.count), 0.4)
        XCTAssertLessThan(Double(goals.count) / Double(sessions.count), 0.8)
        for session in sessions {
            if let goal = session.mode.goalMinutes {
                XCTAssertTrue([25, 50, 90].contains(goal))
                if session.outcome == .bailed {
                    XCTAssertLessThan(session.duration, TimeInterval(goal * 60))
                } else {
                    XCTAssertEqual(session.duration, TimeInterval(goal * 60))
                }
            } else {
                XCTAssertEqual(session.outcome, .completed, "open sessions never bail")
            }
        }
    }

    func testUsesOnlyTheGivenSubjects() {
        let subjects = DemoData.defaultSubjects(now: now)
        let namesByID = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.name) })
        let sessions = DemoData.generate(subjects: subjects, now: now, calendar: calendar)

        for session in sessions {
            XCTAssertEqual(namesByID[session.subjectID], session.subjectName)
        }
        XCTAssertEqual(Set(sessions.map(\.subjectName)), ["CS128", "MATH241"])
    }

    func testNothingEndsAfterNowEarlyInTheMorning() {
        let earlyNow = date(2026, 10, 10, 8, 30)
        let sessions = DemoData.generate(subjects: DemoData.defaultSubjects(now: earlyNow), days: 30,
                                         now: earlyNow, calendar: calendar)

        XCTAssertFalse(sessions.isEmpty)
        XCTAssertTrue(sessions.allSatisfy { ($0.end ?? .distantFuture) <= earlyNow })
    }

    func testEmptyInputsGiveNoSessions() {
        XCTAssertEqual(DemoData.generate(subjects: [], now: now, calendar: calendar), [])
        XCTAssertEqual(DemoData.generate(subjects: DemoData.defaultSubjects(now: now), days: 0,
                                         now: now, calendar: calendar), [])
    }
}
