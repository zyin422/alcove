import XCTest
@testable import Accountabilibrosis

final class MirrorTests: XCTestCase {
    private let coldMirror = """
    {"message":"Your priority is Finish the lab. You asked to stop 18 minutes into a 50 minute goal. Are you stuck on this task, or are you forfeiting today's commitment?","interrogation_turn":1,"user_intent_classification":"DRIFT_UNCONSCIOUS","recommended_action":"FORCE_MICRO_STEP","suggested_quick_replies":["I'm stuck","Forfeit today's goal"],"break_minutes":5}
    """

    func testAProseQuestionCanBeAnsweredAndTheFallbackCannot() {
        let prose = MirrorTurn.parse("What is the single next 2-minute physical action?")
        XCTAssertFalse(prose.parsed)
        XCTAssertTrue(MirrorTurn.acceptsReply(prose))
        XCTAssertFalse(MirrorTurn.acceptsReply(.unavailable))
    }

    func testPromptCarriesTheMirrorRules() {
        let prompt = MirrorPrompt.system
        XCTAssertTrue(prompt.contains("Shatter the cognitive trance"))
        XCTAssertTrue(prompt.contains("Maximum 2 to 3 sentences"))
        XCTAssertTrue(prompt.contains("No false compromises"))
        XCTAssertTrue(prompt.contains("Are you stuck on this task"))
        for action in ["FORCE_MICRO_STEP", "START_BREAK_TIMER", "CONFIRM_FORFEIT", "DISMISS_MODAL"] {
            XCTAssertTrue(prompt.contains(action), action)
        }
    }

    func testParseReadsTheContract() {
        let turn = MirrorTurn.parse(coldMirror)
        XCTAssertTrue(turn.parsed)
        XCTAssertEqual(turn.interrogationTurn, 1)
        XCTAssertEqual(turn.action, .forceMicroStep)
        XCTAssertEqual(turn.replies, ["I'm stuck", "Forfeit today's goal"])
        XCTAssertTrue(turn.message.hasPrefix("Your priority is Finish the lab"))
    }

    func testParseFindsJSONAfterProseAndAFence() {
        let fenced = "Here you go:\n```json\n\(coldMirror)\n```"
        XCTAssertEqual(MirrorTurn.parse(fenced).action, .forceMicroStep)
    }

    func testUnusableReplyIsWordsOnly() {
        let turn = MirrorTurn.parse("just keep going")
        XCTAssertFalse(turn.parsed)
        XCTAssertEqual(turn.message, "just keep going")
        XCTAssertNil(turn.action)
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: true), .speak)
    }

    func testOpeningTurnCannotForfeitOrBreak() {
        var turn = MirrorTurn.parse(coldMirror)
        turn.action = .confirmForfeit
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: false), .speak)
        turn.action = .startBreakTimer
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: false), .speak)
    }

    func testAReplyCanForfeitDismissOrBreak() {
        var turn = MirrorTurn.parse(coldMirror)
        turn.action = .confirmForfeit
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: true), .forfeit)
        turn.action = .dismissModal
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: true), .dismiss)
        turn.action = .startBreakTimer
        turn.breakMinutes = 40
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: true), .takeBreak(minutes: 15))
        turn.breakMinutes = 0
        XCTAssertEqual(MirrorTurn.clampedBreak(0), 5)
    }

    @MainActor func testInterrogatorSendsThePromptAndParsesTheReply() async {
        let transport = MockTransport { _ in (200, chatTextBody(self.coldMirror)) }
        let mirror = MirrorInterrogator(apiKey: { "sk-test" }, transport: transport)
        let context = MirrorContext(priority: "Finish the lab", setup: "CS128", elapsedSeconds: 18 * 60,
                                    goalMinutes: 50, reason: "The user asked to end the session early.")
        let turn = await mirror.respond(context: context, history: [])
        XCTAssertEqual(turn.action, .forceMicroStep)
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("Shatter the cognitive trance"))
        XCTAssertTrue(body.contains("Finish the lab"))
        XCTAssertTrue(body.contains("interrogation_turn 1"))
        XCTAssertTrue(body.contains("json_object"))
    }

    @MainActor func testInterrogatorAsksAgainWhenTheReplyIsNotJSON() async {
        var calls = 0
        let transport = MockTransport { _ in
            calls += 1
            let text = calls == 1 ? "What is the next 2-minute action?" : self.coldMirror
            return (200, chatTextBody(text))
        }
        let mirror = MirrorInterrogator(apiKey: { "sk-test" }, transport: transport)
        let turn = await mirror.respond(context: MirrorContext(priority: "Calc241", setup: "CS173",
                                                               elapsedSeconds: 60, goalMinutes: 25, reason: "stop"),
                                        history: [])
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(turn.action, .forceMicroStep)
        XCTAssertTrue(turn.parsed)
    }

    @MainActor func testInterrogatorWithoutAKeyNeverEndsTheSession() async {
        let mirror = MirrorInterrogator(apiKey: { nil }, transport: MockTransport { _ in (500, Data()) })
        let turn = await mirror.respond(context: MirrorContext(priority: "A", setup: "B", elapsedSeconds: 1,
                                                               goalMinutes: 25, reason: "stop"), history: [])
        XCTAssertEqual(turn, .unavailable)
        XCTAssertEqual(MirrorTurn.effect(of: turn, userHasReplied: true), .speak)
    }

    @MainActor func testBreakPausesMonitoringAndRestoresIt() async {
        let h = EngineHarness()
        await h.engine.start(subject: Subject(name: "CS128", sites: ["https://cs128.org"]),
                             mode: .goal(minutes: 50), displayName: "Z")
        let stops = h.chrome.stopWatchCount
        h.engine.beginBreak(minutes: 5)
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, stops + 1)
        XCTAssertEqual(h.engine.breakRemaining ?? 0, 300, accuracy: 1)
        XCTAssertTrue(h.engine.isLocked)

        h.clock.advance(300)
        h.engine.tick()
        XCTAssertNil(h.engine.breakRemaining)
        XCTAssertEqual(h.chrome.watchedSubject, "CS128")
        XCTAssertNotNil(h.blocker.startedWith)
    }

    @MainActor func testGiveUpPhraseUsesThePriorityTheMirrorNames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mirror-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let harness = EngineHarness()
        let model = AppModel(store: Store(fileURL: directory.appendingPathComponent("store.json")),
                             engine: harness.engine)
        let subject = Subject(name: "CS173", sites: ["https://cs173.org"])
        model.addSubject(subject)
        model.updatePlan(day: DayKey.key(for: Date())) {
            $0.priorities = [Priority(title: "Calc241", subjectID: subject.id)]
        }
        await model.lockIn(subjectID: subject.id, mode: .goal(minutes: 25))

        XCTAssertEqual(model.mirrorTaskName, "Calc241")
        XCTAssertEqual(model.mirrorContext(reason: "stop").setup, "CS173")
        XCTAssertEqual(model.engine.giveUpPhrase(template: "I give up on {subject}", name: model.mirrorTaskName),
                       "I give up on Calc241")
    }

    @MainActor func testBreakWhileIdleDoesNothing() {
        let h = EngineHarness()
        h.engine.beginBreak(minutes: 5)
        XCTAssertNil(h.engine.breakRemaining)
        XCTAssertEqual(h.blocker.stopCount, 0)
    }
}
