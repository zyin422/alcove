import XCTest
@testable import Alcove

/// Records the companion events the engine sends.
@MainActor private final class FakeCompanion: CompanionReacting {
    enum Event: Equatable {
        case started(subject: String, goal: TimeInterval?)
        case violation(kind: CompanionViolation, subject: String, violations: Int)
        case ended(outcome: SessionOutcome, subject: String)
    }
    var events: [Event] = []

    func sessionDidStart(subject: String, goalSeconds: TimeInterval?) {
        events.append(.started(subject: subject, goal: goalSeconds))
    }
    func violationOccurred(_ kind: CompanionViolation, subject: String, violations: Int) {
        events.append(.violation(kind: kind, subject: subject, violations: violations))
    }
    func sessionDidEnd(outcome: SessionOutcome, subject: String) {
        events.append(.ended(outcome: outcome, subject: subject))
    }
}

@MainActor
final class CompanionWiringTests: XCTestCase {
    private func makeSubject() -> Subject {
        Subject(name: "CS128", preset: .full, sites: ["https://cs128.org/schedule"])
    }

    func testStartTellsCompanionSubjectAndGoal() async {
        let h = EngineHarness()
        let companion = FakeCompanion()
        h.engine.companion = companion
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(companion.events, [.started(subject: "CS128", goal: TimeInterval(25 * 60))])
    }

    func testOpenModeStartHasNoGoal() async {
        let h = EngineHarness()
        let companion = FakeCompanion()
        h.engine.companion = companion
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(companion.events, [.started(subject: "CS128", goal: nil)])
    }

    func testBlockedAppAndClosedTabCountAsViolationsTogether() async {
        let h = EngineHarness()
        let companion = FakeCompanion()
        h.engine.companion = companion
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        h.chrome.simulateTabClosed("youtube.com")
        h.blocker.simulateBlocked("com.apple.Notes", name: "Notes")

        XCTAssertEqual(Array(companion.events.dropFirst()), [
            .violation(kind: .app(name: "Discord"), subject: "CS128", violations: 1),
            .violation(kind: .tab(host: "youtube.com"), subject: "CS128", violations: 2),
            .violation(kind: .app(name: "Notes"), subject: "CS128", violations: 3),
        ])
    }

    func testFinishTellsCompanionCompleted() async {
        let h = EngineHarness()
        let companion = FakeCompanion()
        h.engine.companion = companion
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        await h.engine.finish()

        XCTAssertEqual(companion.events.last, .ended(outcome: .completed, subject: "CS128"))
    }

    func testEarlyBailTellsCompanionBailed() async {
        let h = EngineHarness()
        let companion = FakeCompanion()
        h.engine.companion = companion
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")
        await h.engine.bail()

        XCTAssertEqual(companion.events.last, .ended(outcome: .bailed, subject: "CS128"))
    }
}
