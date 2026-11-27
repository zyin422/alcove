import XCTest
@testable import Alcove

final class MirrorTests: XCTestCase {
    private let coldMirror = """
    {"message":"Your priority is Finish the lab. You asked to stop 18 minutes into a 50 minute goal. Are you stuck on this task, or are you forfeiting today's commitment?","interrogation_turn":1,"user_intent_classification":"DRIFT_UNCONSCIOUS","recommended_action":"FORCE_MICRO_STEP","suggested_quick_replies":["I'm stuck","Forfeit today's goal"],"break_minutes":5}
    """

    func testEndingOffersTheThreeChoicesImmediately() {
        XCTAssertEqual(MirrorTurn.openingChoices.replies, ["I want to stop", "I need help starting", "I need a break"])
        XCTAssertEqual(MirrorTurn.effect(of: .openingChoices, userHasReplied: false), .speak)
    }

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

    func testHelpGettingStartedGivesAStepInsteadOfEnding() {
        XCTAssertEqual(MirrorPathway.classify("I need help starting"), .helpStarting)
        XCTAssertEqual(MirrorPathway.classify("I want help to get started"), .helpStarting)
        XCTAssertEqual(MirrorPathway.classify("I'm stuck"), .helpStarting)

        let forfeited = MirrorTurn(message: "Session ended.", interrogationTurn: 2, intent: "INTENTIONAL_FORFEIT",
                                   action: .confirmForfeit, replies: MirrorTurn.choiceReplies,
                                   breakMinutes: 5, parsed: true)
        let fixed = MirrorTurn.applying(forfeited, userSaid: "I want help to get started", task: "Calc241")
        XCTAssertEqual(fixed.action, .forceMicroStep)
        XCTAssertEqual(fixed.replies, ["I'll do that", "That's not the step"])
        XCTAssertEqual(fixed.message, "Next two minutes: open Calc241 and do the first physical step. Nothing else.")
        XCTAssertEqual(MirrorTurn.effect(of: fixed, userHasReplied: true), .speak)

        let step = MirrorTurn(message: "Open the Calc241 tab and write the first line.", interrogationTurn: 2,
                              intent: "STUCK_AMBIGUOUS", action: .forceMicroStep, replies: [],
                              breakMinutes: 5, parsed: true)
        let kept = MirrorTurn.applying(step, userSaid: "I need help starting", task: "Calc241")
        XCTAssertEqual(kept.message, "Open the Calc241 tab and write the first line.")
        XCTAssertEqual(kept.replies, MirrorPathway.helpReplies)

        let accepted = MirrorTurn.applying(step, userSaid: "I'll do that", task: "Calc241")
        XCTAssertEqual(MirrorTurn.effect(of: accepted, userHasReplied: true), .dismiss)
        let another = MirrorTurn.applying(step, userSaid: "That's not the step", task: "Calc241")
        XCTAssertEqual(another.action, .forceMicroStep)
        XCTAssertEqual(another.replies, MirrorPathway.helpReplies)
    }

    func testStopConfirmsBeforeItForfeitsAndABreakStarts() {
        let early = MirrorTurn(message: "Ending it.", interrogationTurn: 2, intent: "INTENTIONAL_FORFEIT",
                               action: .confirmForfeit, replies: [], breakMinutes: 5, parsed: true)
        let confirm = MirrorTurn.applying(early, userSaid: "I want to stop", task: "Calc241")
        XCTAssertEqual(confirm.action, .forceMicroStep)
        XCTAssertEqual(confirm.replies, ["Yes, end it", "No, keep working"])
        XCTAssertEqual(MirrorTurn.effect(of: confirm, userHasReplied: true), .speak)

        let yes = MirrorTurn.applying(early, userSaid: "Yes, end it", task: "Calc241")
        XCTAssertEqual(MirrorTurn.effect(of: yes, userHasReplied: true), .forfeit)

        let stay = MirrorTurn.applying(early, userSaid: "No, keep working", task: "Calc241")
        XCTAssertEqual(MirrorTurn.effect(of: stay, userHasReplied: true), .dismiss)

        let asked = MirrorTurn(message: "What is the next 2-minute action?", interrogationTurn: 2, intent: "",
                               action: .forceMicroStep, replies: MirrorTurn.choiceReplies, breakMinutes: 5, parsed: true)
        let brake = MirrorTurn.applying(asked, userSaid: "I need a break", task: "Calc241")
        XCTAssertEqual(MirrorTurn.effect(of: brake, userHasReplied: true), .takeBreak(minutes: 5))
        XCTAssertTrue(brake.message.contains("Five minutes"))
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

    @MainActor func testHelpStartingTellsTheModelWhichPathToTake() async {
        let transport = MockTransport { _ in (200, chatTextBody(self.coldMirror)) }
        let mirror = MirrorInterrogator(apiKey: { "sk-test" }, transport: transport)
        _ = await mirror.respond(context: MirrorContext(priority: "Calc241", setup: "CS173", elapsedSeconds: 60,
                                                       goalMinutes: 0, reason: "stop"),
                                history: [.user("I want help to get started")])
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("I want help to get started"))
        XCTAssertTrue(body.contains("Give one concrete 2-minute physical action"))
        XCTAssertTrue(body.contains("Do not forfeit"))
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
        h.workspace.hideResult = ["com.hnc.Discord"]
        await h.engine.start(subject: Subject(name: "CS128", sites: ["https://cs128.org"]),
                             mode: .goal(minutes: 50), displayName: "Z")
        h.blocker.simulateBlocked("com.spotify.client", name: "Spotify")
        let stops = h.chrome.stopWatchCount
        h.clock.advance(SessionEngine.breakCooldown)
        h.engine.allowsOffTaskDuringBreak = { true }
        XCTAssertTrue(h.engine.beginBreak(minutes: 5))
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, stops + 1)
        XCTAssertTrue(h.workspace.unhideCalls.isEmpty, "a break does not bring hidden apps back")
        XCTAssertTrue(h.workspace.relaunchCalls.isEmpty)
        XCTAssertEqual(h.engine.breakRemaining ?? 0, 300, accuracy: 1)
        XCTAssertTrue(h.engine.isLocked)

        h.clock.advance(300)
        h.engine.tick()
        XCTAssertNil(h.engine.breakRemaining)
        XCTAssertEqual(h.chrome.watchedSubject, "CS128")
        XCTAssertEqual(h.chrome.closeUnrelatedCount, 1)
        XCTAssertEqual(h.workspace.hideCalls.count, 2, "apps opened during the break are hidden")
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

    func testMirrorContextFormatsTelemetryInPrompt() {
        let context = MirrorContext(priority: "CS128 lab", setup: "CS128", elapsedSeconds: 840,
                                    goalMinutes: 45, reason: "Bail requested",
                                    blockedAttempts: 3, closedTabs: 2)
        let opening = context.userMessage(isOpening: true)
        XCTAssertTrue(opening.contains("Distraction apps blocked this session: 3 times."))
        XCTAssertTrue(opening.contains("Off-task browser tabs closed this session: 2 tabs."))
        XCTAssertTrue(opening.contains("Active priority: CS128 lab"))
    }

    @MainActor func testBreakWhileIdleDoesNothing() {
        let h = EngineHarness()
        h.engine.beginBreak(minutes: 5)
        XCTAssertNil(h.engine.breakRemaining)
        XCTAssertEqual(h.blocker.stopCount, 0)
    }
}
