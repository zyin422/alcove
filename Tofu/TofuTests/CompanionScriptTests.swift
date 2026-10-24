import XCTest
@testable import Tofu

final class CompanionScriptTests: XCTestCase {
    /// Deterministic pick: always the first line of a table.
    private let first: (Int) -> Int = { _ in 0 }

    // MARK: Resting face

    func testRestsCalmUntilDistractionsPileUp() {
        XCTAssertEqual(CompanionScript.concernThreshold, 3)
        XCTAssertEqual(CompanionScript.restingExpression(violations: 0), .calm)
        XCTAssertEqual(CompanionScript.restingExpression(violations: 2), .calm)
        XCTAssertEqual(CompanionScript.restingExpression(violations: 3), .worried)
    }

    // MARK: Lines

    func testBlockedAppLineMentionsTheAppForEveryPersonality() {
        for personality in CompanionPersonality.allCases {
            let line = CompanionScript.line(for: .blockedApp(name: "Discord"), personality: personality,
                                            violations: 0, pick: first)
            XCTAssertTrue(line.text.contains("Discord"), "\(personality)")
            XCTAssertEqual(line.expression, .worried)
        }
    }

    func testClosedTabLineMentionsTheHost() {
        for personality in CompanionPersonality.allCases {
            let line = CompanionScript.line(for: .closedTab(host: "youtube.com"), personality: personality,
                                            violations: 0, pick: first)
            XCTAssertTrue(line.text.contains("youtube.com"), "\(personality)")
        }
    }

    func testSessionStartLineMentionsTheSubject() {
        for personality in CompanionPersonality.allCases {
            let line = CompanionScript.line(for: .sessionStart(subject: "CS128"), personality: personality,
                                            violations: 0, pick: first)
            XCTAssertTrue(line.text.contains("CS128"), "\(personality)")
        }
    }

    func testRecallQuotesTheNote() {
        let note = "You were on recursion in MP3."
        for personality in CompanionPersonality.allCases {
            let line = CompanionScript.line(for: .recall(subject: "CS128", note: note), personality: personality,
                                            violations: 0, pick: first)
            XCTAssertTrue(line.text.contains(note), "\(personality)")
        }
    }

    func testFirmLinesAfterRepeatedDistractions() {
        let early = CompanionScript.line(for: .blockedApp(name: "Discord"), personality: .playful,
                                         violations: 0, pick: first)
        let firm = CompanionScript.line(for: .blockedApp(name: "Discord"), personality: .playful,
                                        violations: 3, pick: first)
        XCTAssertNotEqual(early.text, firm.text)
        XCTAssertTrue(firm.text.contains("Discord"))
    }

    func testCompletedAndHalfwayAreHappy() {
        for personality in CompanionPersonality.allCases {
            XCTAssertEqual(CompanionScript.line(for: .completed, personality: personality,
                                                violations: 0, pick: first).expression, .happy)
            XCTAssertEqual(CompanionScript.line(for: .halfway, personality: personality,
                                                violations: 0, pick: first).expression, .happy)
        }
    }

    func testForfeitIsWorriedNotHarsh() {
        for personality in CompanionPersonality.allCases {
            XCTAssertEqual(CompanionScript.line(for: .forfeit, personality: personality,
                                                violations: 0, pick: first).expression, .worried)
        }
    }

    func testNoAnimeTropesLeft() {
        let events: [CompanionEvent] = [.sessionStart(subject: "X"), .blockedApp(name: "A"), .closedTab(host: "h"),
                                        .halfway, .completed, .forfeit, .idle, .recall(subject: "X", note: "n")]
        for personality in CompanionPersonality.allCases {
            for event in events {
                for index in 0..<4 {
                    let text = CompanionScript.line(for: event, personality: personality, violations: 0,
                                                    pick: { _ in index }).text.lowercased()
                    XCTAssertFalse(text.contains("baka"))
                    XCTAssertFalse(text.contains("♥"))
                }
            }
        }
    }

    func testPickChoosesAmongSeveralLines() {
        let a = CompanionScript.line(for: .idle, personality: .gentle, violations: 0, pick: { _ in 0 })
        let b = CompanionScript.line(for: .idle, personality: .gentle, violations: 0, pick: { _ in 1 })
        XCTAssertNotEqual(a.text, b.text)
    }

    func testOutOfRangePickIsClampedInsteadOfCrashing() {
        let line = CompanionScript.line(for: .idle, personality: .wise, violations: 0, pick: { _ in 999 })
        XCTAssertFalse(line.text.isEmpty)
    }

    func testPickReceivesTheTableSize() {
        var seenCount = 0
        _ = CompanionScript.line(for: .idle, personality: .gentle, violations: 0,
                                 pick: { count in seenCount = count; return 0 })
        XCTAssertGreaterThanOrEqual(seenCount, 2)
    }

    // MARK: Pose

    func testPoseBreathesSwaysAndBlinks() {
        XCTAssertEqual(MossPose(time: 0).breath, 0, accuracy: 0.0001)
        XCTAssertFalse(MossPose(time: 0).isBlinking)
        XCTAssertEqual(MossPose(time: 0.8).breath, 1, accuracy: 0.0001)
        XCTAssertTrue(MossPose(time: 4.25).isBlinking)
        XCTAssertFalse(MossPose(time: 4.5).isBlinking)
        XCTAssertLessThanOrEqual(abs(MossPose(time: 0.65).sway), 7)
    }
}
