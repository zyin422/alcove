import XCTest
@testable import Tofu

final class CompanionScriptTests: XCTestCase {
    /// Deterministic pick: always the first line of a table.
    private let first: (Int) -> Int = { _ in 0 }

    // MARK: Mood

    func testPureTsundereStaysTsundereHoweverManyViolations() {
        XCTAssertEqual(CompanionScript.mood(for: .tsundere, violations: 0), .tsundere)
        XCTAssertEqual(CompanionScript.mood(for: .tsundere, violations: 99), .tsundere)
    }

    func testPureYandereIsAlwaysYandere() {
        XCTAssertEqual(CompanionScript.mood(for: .yandere, violations: 0), .yandere)
        XCTAssertEqual(CompanionScript.mood(for: .yandere, violations: 99), .yandere)
    }

    func testEscalationStartsTsundere() {
        XCTAssertEqual(CompanionScript.mood(for: .escalation, violations: 0), .tsundere)
        XCTAssertEqual(CompanionScript.mood(for: .escalation, violations: 2), .tsundere)
    }

    func testEscalationTurnsYandereAtThreeViolations() {
        XCTAssertEqual(CompanionScript.escalationThreshold, 3)
        XCTAssertEqual(CompanionScript.mood(for: .escalation, violations: 3), .yandere)
        XCTAssertEqual(CompanionScript.mood(for: .escalation, violations: 10), .yandere)
    }

    // MARK: Lines

    func testBlockedAppLineMentionsTheApp() {
        let line = CompanionScript.line(for: .blockedApp(name: "Discord"),
                                        personality: .tsundere, violations: 0, pick: first)
        XCTAssertTrue(line.text.contains("Discord"))
    }

    func testClosedTabLineMentionsTheHost() {
        let line = CompanionScript.line(for: .closedTab(host: "youtube.com"),
                                        personality: .tsundere, violations: 0, pick: first)
        XCTAssertTrue(line.text.contains("youtube.com"))
    }

    func testSessionStartLineMentionsTheSubject() {
        let line = CompanionScript.line(for: .sessionStart(subject: "CS128"),
                                        personality: .tsundere, violations: 0, pick: first)
        XCTAssertTrue(line.text.contains("CS128"))
    }

    func testTsundereScoldLooksAnnoyed() {
        let app = CompanionScript.line(for: .blockedApp(name: "Discord"),
                                       personality: .tsundere, violations: 0, pick: first)
        let tab = CompanionScript.line(for: .closedTab(host: "youtube.com"),
                                       personality: .tsundere, violations: 0, pick: first)
        XCTAssertEqual(app.expression, .annoyed)
        XCTAssertEqual(tab.expression, .annoyed)
    }

    func testYandereScoldLooksDark() {
        let line = CompanionScript.line(for: .blockedApp(name: "Discord"),
                                        personality: .yandere, violations: 0, pick: first)
        XCTAssertEqual(line.expression, .dark)
    }

    func testEscalatedScoldUsesYandereLines() {
        let calm = CompanionScript.line(for: .blockedApp(name: "Discord"),
                                        personality: .escalation, violations: 0, pick: first)
        let escalated = CompanionScript.line(for: .blockedApp(name: "Discord"),
                                             personality: .escalation, violations: 3, pick: first)
        XCTAssertEqual(calm.expression, .annoyed)
        XCTAssertEqual(escalated.expression, .dark)
        XCTAssertNotEqual(calm.text, escalated.text)
    }

    func testCompletedLineIsPleasedInBothMoods() {
        XCTAssertEqual(CompanionScript.line(for: .completed, personality: .tsundere,
                                            violations: 0, pick: first).expression, .pleased)
        XCTAssertEqual(CompanionScript.line(for: .completed, personality: .yandere,
                                            violations: 0, pick: first).expression, .pleased)
    }

    func testIdleLineIsNeutral() {
        XCTAssertEqual(CompanionScript.line(for: .idle, personality: .tsundere,
                                            violations: 0, pick: first).expression, .neutral)
        XCTAssertEqual(CompanionScript.line(for: .idle, personality: .yandere,
                                            violations: 0, pick: first).expression, .neutral)
    }

    func testForfeitIsAnnoyedForTsundereDarkForYandere() {
        XCTAssertEqual(CompanionScript.line(for: .forfeit, personality: .tsundere,
                                            violations: 0, pick: first).expression, .annoyed)
        XCTAssertEqual(CompanionScript.line(for: .forfeit, personality: .yandere,
                                            violations: 0, pick: first).expression, .dark)
    }

    func testHalfwayLineIsPleased() {
        XCTAssertEqual(CompanionScript.line(for: .halfway, personality: .tsundere,
                                            violations: 0, pick: first).expression, .pleased)
    }

    func testPickChoosesAmongSeveralLines() {
        let a = CompanionScript.line(for: .idle, personality: .tsundere, violations: 0, pick: { _ in 0 })
        let b = CompanionScript.line(for: .idle, personality: .tsundere, violations: 0, pick: { _ in 1 })
        XCTAssertNotEqual(a.text, b.text)
    }

    func testOutOfRangePickIsClampedInsteadOfCrashing() {
        let line = CompanionScript.line(for: .idle, personality: .tsundere, violations: 0, pick: { _ in 999 })
        XCTAssertFalse(line.text.isEmpty)
    }

    func testPickReceivesTheTableSize() {
        var seenCount = 0
        _ = CompanionScript.line(for: .idle, personality: .tsundere, violations: 0,
                                 pick: { count in seenCount = count; return 0 })
        XCTAssertGreaterThanOrEqual(seenCount, 2)
    }
}
