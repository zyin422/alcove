import XCTest
@testable import Tofu

final class TechTreeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    private func makeSubject(name: String = "Algorithms") -> Subject {
        Subject(name: name)
    }

    private func makeSession(subjectID: UUID, minutes: Int, start: Date, blocked: Int = 0, closed: Int = 0, outcome: SessionOutcome = .completed) -> Session {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return Session(
            subjectID: subjectID,
            subjectName: "Test",
            mode: .goal(minutes: minutes),
            start: start,
            end: end,
            lastHeartbeat: end,
            blockedAttempts: blocked,
            closedTabs: closed,
            outcome: outcome
        )
    }

    func testNoviceTierForNewSubject() {
        let subject = makeSubject()
        let mastery = TechTreeEngine.computeMastery(for: subject, sessions: [], priorities: [], calendar: calendar)

        XCTAssertEqual(mastery.tier, .novice)
        XCTAssertEqual(mastery.level, 1)
        XCTAssertEqual(mastery.xp, 0)
        XCTAssertEqual(mastery.totalSeconds, 0)
        XCTAssertEqual(mastery.progressToNextTier, 0.0)
        XCTAssertEqual(mastery.unlockedBadges.count, 0)
        XCTAssertEqual(mastery.lockedBadges.count, MasteryBadgeID.allCases.count)
    }

    func testApprenticeTierUnlockedAtTwoHours() {
        let subject = makeSubject()
        // 130 minutes total = 2h 10m
        let s1 = makeSession(subjectID: subject.id, minutes: 70, start: date(2026, 11, 20, 10))
        let s2 = makeSession(subjectID: subject.id, minutes: 60, start: date(2026, 11, 21, 10))

        let mastery = TechTreeEngine.computeMastery(for: subject, sessions: [s1, s2], priorities: [], calendar: calendar)

        XCTAssertEqual(mastery.tier, .apprentice)
        XCTAssertGreaterThan(mastery.level, 1)
        XCTAssertEqual(mastery.totalSeconds, 130 * 60)
        // Apprentice range: 2h (7200s) to 10h (36000s). (7800 - 7200) / (36000 - 7200) = 600 / 28800 ~= 0.0208
        XCTAssertEqual(mastery.progressToNextTier, 600.0 / 28800.0, accuracy: 0.001)
    }

    func testPractitionerAndSpecialistTiers() {
        let subject = makeSubject()
        // 12 hours = 720 minutes -> Practitioner
        let s = makeSession(subjectID: subject.id, minutes: 12 * 60, start: date(2026, 11, 20, 9))
        let mastery = TechTreeEngine.computeMastery(for: subject, sessions: [s], priorities: [], calendar: calendar)

        XCTAssertEqual(mastery.tier, .practitioner)
        XCTAssertEqual(mastery.tier.next, .specialist)
    }

    func testXPCalculationIncludesCleanSessionAndPriorityBonuses() {
        let subject = makeSubject()
        // 60 minutes = 600 XP base
        // 0 blocked, 0 closed = 25 XP clean bonus
        let session = makeSession(subjectID: subject.id, minutes: 60, start: date(2026, 11, 20, 10), blocked: 0, closed: 0)

        // 2 done priorities = 2 * 50 = 100 XP bonus
        let p1 = Priority(title: "Task 1", subjectID: subject.id, isDone: true)
        let p2 = Priority(title: "Task 2", subjectID: subject.id, isDone: true)
        let p3 = Priority(title: "Task 3 (undone)", subjectID: subject.id, isDone: false)

        let mastery = TechTreeEngine.computeMastery(for: subject, sessions: [session], priorities: [p1, p2, p3], calendar: calendar)

        let expectedXP = (60 * 10) + 25 + (2 * 50)
        XCTAssertEqual(mastery.xp, expectedXP)
        XCTAssertEqual(mastery.completedPrioritiesCount, 2)
    }

    func testBadgeUnlocks() {
        let subject = makeSubject()
        // Day 1: 95 min session, 0 violations -> First Step + Deep Focus
        let s1 = makeSession(subjectID: subject.id, minutes: 95, start: date(2026, 11, 20, 10), blocked: 0, closed: 0)
        // Day 2: 30 min session -> Century mark (125 min total)
        let s2 = makeSession(subjectID: subject.id, minutes: 30, start: date(2026, 11, 21, 10))
        // Day 3: 20 min session -> Daily Devotion (3 distinct days)
        let s3 = makeSession(subjectID: subject.id, minutes: 20, start: date(2026, 11, 22, 10))

        var priorities: [Priority] = []
        for i in 1...5 {
            priorities.append(Priority(title: "Priority \(i)", subjectID: subject.id, isDone: true))
        }

        let mastery = TechTreeEngine.computeMastery(
            for: subject,
            sessions: [s1, s2, s3],
            priorities: priorities,
            calendar: calendar
        )

        let unlockedIDs = Set(mastery.unlockedBadges.map(\.id))
        XCTAssertTrue(unlockedIDs.contains(.firstStep))
        XCTAssertTrue(unlockedIDs.contains(.deepFocus))
        XCTAssertTrue(unlockedIDs.contains(.centuryMark))
        XCTAssertTrue(unlockedIDs.contains(.dailyDevotion))
        XCTAssertTrue(unlockedIDs.contains(.priorityCrusher))
    }

    func testComputeAllMatchesSubjectIDs() {
        let subA = makeSubject(name: "Sub A")
        let subB = makeSubject(name: "Sub B")

        let sA = makeSession(subjectID: subA.id, minutes: 60, start: date(2026, 11, 20, 10))
        let pB = Priority(title: "PB", subjectID: subB.id, isDone: true)
        let plan = DayPlan(day: "2026-11-20", priorities: [pB])

        let results = TechTreeEngine.computeAll(
            subjects: [subA, subB],
            sessions: [sA],
            plans: [plan],
            calendar: calendar
        )

        XCTAssertEqual(results.count, 2)
        let resA = results.first { $0.subject.id == subA.id }!
        let resB = results.first { $0.subject.id == subB.id }!

        XCTAssertEqual(resA.totalSeconds, 3600)
        XCTAssertEqual(resA.completedPrioritiesCount, 0)

        XCTAssertEqual(resB.totalSeconds, 0)
        XCTAssertEqual(resB.completedPrioritiesCount, 1)
    }
}
