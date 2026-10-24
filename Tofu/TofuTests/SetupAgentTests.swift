import XCTest
@testable import Tofu

final class SetupAgentToolsTests: XCTestCase {
    private let vscode = AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
    private let notion = AllowedApp(bundleID: "notion.id", name: "Notion")

    private func lookup(_ name: String) -> AllowedApp? {
        let lower = name.lowercased()
        if lower.contains("code") { return vscode }
        if lower.contains("notion") { return notion }
        return nil
    }

    private func apply(_ name: String, _ arguments: [String: String], _ form: inout SubjectFormState)
        -> SetupAgentTools.Outcome {
        SetupAgentTools.apply(name: name, arguments: arguments, to: &form, lookupApp: lookup)
    }

    func testArgumentsReadStringsNumbersAndLists() {
        let parsed = SetupAgentTools.arguments(#"{"window": 2, "kind": "website", "urls": ["a.com", "b.com"], "x": null}"#)
        XCTAssertEqual(parsed["window"], "2")
        XCTAssertEqual(parsed["kind"], "website")
        XCTAssertEqual(parsed["urls"], "a.com, b.com")
        XCTAssertNil(parsed["x"])
        XCTAssertEqual(SetupAgentTools.arguments("not json"), [:])
    }

    func testLayoutNames() {
        XCTAssertEqual(SetupAgentTools.layout("left_right"), .split)
        XCTAssertEqual(SetupAgentTools.layout("Full"), .full)
        XCTAssertEqual(SetupAgentTools.layout("thirds"), .thirds)
        XCTAssertEqual(SetupAgentTools.layout("70/30"), .mainSide)
        XCTAssertNil(SetupAgentTools.layout("diagonal"))
    }

    func testUpdateSetupChangesOnlyGivenFields() {
        var form = SubjectFormState(subject: nil)
        let outcome = apply("update_setup", ["name": "CS128", "layout": "thirds", "browser": "arc"], &form)
        XCTAssertEqual(form.name, "CS128")
        XCTAssertEqual(form.preset, .thirds)
        XCTAssertEqual(form.browser, .arc)
        XCTAssertEqual(form.unusedApps, .hide)
        XCTAssertEqual(outcome.changes, ["Name → CS128", "Layout → Thirds", "Browser → Arc"])
    }

    func testUpdateSetupReportsBadValues() {
        var form = SubjectFormState(subject: nil)
        let outcome = apply("update_setup", ["layout": "diagonal", "other_apps": "explode"], &form)
        XCTAssertEqual(outcome.changes, [])
        XCTAssertTrue(outcome.result.contains("Unknown layout"))
        XCTAssertTrue(outcome.result.contains("Unknown other_apps"))
    }

    func testSetWebsiteWindow() {
        var form = SubjectFormState(subject: nil)
        form.preset = .full
        let outcome = apply("set_window", ["window": "1", "kind": "website",
                                           "urls": "https://cs128.org, prairielearn.org"], &form)
        XCTAssertEqual(form.zoneSlots[0].kind, .website)
        XCTAssertEqual(form.zoneSlots[0].urls, ["https://cs128.org", "prairielearn.org"])
        XCTAssertEqual(outcome.changes, ["Window 1 → cs128.org, prairielearn.org"])
    }

    func testSecondWindowSwitchesToATwoWindowLayout() {
        var form = SubjectFormState(subject: nil)
        form.preset = .full
        let outcome = apply("set_window", ["window": "2", "kind": "app", "app": "VS Code", "folder": "~/code/mp3"], &form)
        XCTAssertEqual(form.preset, .split)
        XCTAssertEqual(form.zoneSlots[1].kind, .app)
        XCTAssertEqual(form.zoneSlots[1].app, vscode)
        XCTAssertEqual(form.zoneSlots[1].folder, "~/code/mp3")
        XCTAssertEqual(outcome.changes.first, "Layout → Left / Right")
    }

    func testSetWindowRejectsMissingAppAndBadIndex() {
        var form = SubjectFormState(subject: nil)
        XCTAssertTrue(apply("set_window", ["window": "1", "kind": "app", "app": "Photoshop"], &form)
            .result.contains("isn't installed"))
        XCTAssertEqual(apply("set_window", ["window": "3", "kind": "website", "urls": "a.com"], &form).result,
                       "window must be 1 or 2.")
        XCTAssertEqual(apply("set_window", ["window": "1", "kind": "website", "urls": " "], &form).result,
                       "Give at least one URL.")
    }

    func testAllowAndRemoveApps() {
        var form = SubjectFormState(subject: nil)
        let allowed = apply("allow_apps", ["apps": "Notion, Photoshop"], &form)
        XCTAssertEqual(form.allowedApps, [notion])
        XCTAssertEqual(allowed.changes, ["Allow Notion"])
        XCTAssertTrue(allowed.result.contains("Not installed: Photoshop"))
        XCTAssertEqual(apply("allow_apps", ["apps": "notion"], &form).changes, [])
        XCTAssertEqual(apply("remove_allowed_app", ["app": "Notion"], &form).changes, ["Stop allowing Notion"])
        XCTAssertTrue(form.allowedApps.isEmpty)
        XCTAssertEqual(apply("remove_allowed_app", ["app": "Notion"], &form).result, "That app wasn't allowed.")
    }

    func testDescribeListsTheSetupAndProblems() {
        var form = SubjectFormState(subject: nil)
        form.preset = .full
        let text = SetupAgentTools.describe(form)
        XCTAssertTrue(text.contains("Name: (none yet)"))
        XCTAssertTrue(text.contains("Layout: Full"))
        XCTAssertTrue(text.contains("Window 1: website (empty)"))
        XCTAssertTrue(text.contains("Problems:"))
    }
}

@MainActor final class SetupAgentConversationTests: XCTestCase {
    private func reply(content: String?, toolCalls: [(id: String, name: String, arguments: String)] = []) -> Data {
        var message: [String: Any] = ["role": "assistant", "content": content ?? NSNull()]
        if !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls.map {
                ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
            }
        }
        return try! JSONSerialization.data(withJSONObject: ["choices": [["message": message]]])
    }

    func testToolCallsChangeTheFormThenTheAgentReplies() async throws {
        var step = 0
        let transport = MockTransport { _ in
            step += 1
            if step == 1 {
                return (200, self.reply(content: nil, toolCalls: [
                    ("c1", "update_setup", #"{"name":"CS128","layout":"full"}"#),
                    ("c2", "set_window", #"{"window":1,"kind":"website","urls":"https://cs128.org"}"#),
                ]))
            }
            return (200, self.reply(content: "Set up CS128 with the course site, full screen."))
        }
        var form = SubjectFormState(subject: nil)
        let agent = SetupAgent(apiKey: { "sk-test" }, transport: transport, lookupApp: { _ in nil }, isNewSubject: true)
        agent.read = { form }
        agent.apply = { change in change(&form) }
        agent.greet(name: "", lastNote: nil)

        await agent.send("CS128, just the course site")

        XCTAssertEqual(form.name, "CS128")
        XCTAssertEqual(form.preset, .full)
        XCTAssertEqual(form.zoneSlots[0].urls, ["https://cs128.org"])
        XCTAssertTrue(form.errors.isEmpty)
        XCTAssertEqual(agent.messages.map(\.role), [.agent, .user, .agent])
        XCTAssertEqual(agent.messages.last?.text, "Set up CS128 with the course site, full screen.")
        XCTAssertEqual(agent.messages.last?.changes, ["Name → CS128", "Layout → Full", "Window 1 → cs128.org"])
        XCTAssertFalse(agent.isThinking)

        // The second request carried the tool results and the current setup in the system prompt.
        let body = try XCTUnwrap(transport.requests.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.first?["content"] as? String ?? "").contains("Name: CS128"))
        XCTAssertEqual(messages.filter { $0["role"] as? String == "tool" }.count, 2)
    }

    func testContextIsAppendedToTheSystemPrompt() async throws {
        let transport = MockTransport { _ in (200, self.reply(content: "Hi")) }
        let agent = SetupAgent(apiKey: { "sk" }, transport: transport, lookupApp: { _ in nil },
                               context: { "Still on the calendar today:\n- 2:00 PM: CS128 lecture" })
        agent.read = { SubjectFormState(subject: nil) }
        await agent.send("hi")
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.first?["content"] as? String ?? "").contains("CS128 lecture"))
    }

    func testWithoutAKeyItSaysSoAndChangesNothing() async {
        let transport = MockTransport { _ in (500, Data()) }
        var form = SubjectFormState(subject: nil)
        let original = form
        let agent = SetupAgent(apiKey: { nil }, transport: transport, lookupApp: { _ in nil })
        agent.read = { form }
        agent.apply = { change in change(&form) }
        await agent.send("hello")
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(agent.messages.last?.text.contains("OpenAI API key") ?? false)
        XCTAssertEqual(form, original)
    }

    func testStartLockInIsNeverOffered() async {
        let transport = MockTransport { _ in (200, self.reply(content: "Press LOCK IN when you're ready.")) }
        let form = SubjectFormState(subject: Subject(name: "CS128", preset: .full, sites: ["https://cs128.org"]))
        for isNew in [false, true] {
            let agent = SetupAgent(apiKey: { "sk" }, transport: transport, lookupApp: { _ in nil }, isNewSubject: isNew)
            agent.read = { form }
            await agent.send("lock in for 50")
        }
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests {
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(body.contains("start_lock_in"))
            XCTAssertTrue(body.contains("update_setup"))
            XCTAssertTrue(body.contains("LOCK IN button"))
        }
    }

    func testOnlyTheNewSubjectSheetMentionsSaving() async {
        let transport = MockTransport { _ in (200, self.reply(content: "Hi")) }
        let form = SubjectFormState(subject: nil)
        for isNew in [true, false] {
            let agent = SetupAgent(apiKey: { "sk" }, transport: transport, lookupApp: { _ in nil }, isNewSubject: isNew)
            agent.read = { form }
            await agent.send("hi")
        }
        let bodies = transport.requests.map { String(data: $0.httpBody ?? Data(), encoding: .utf8) ?? "" }
        XCTAssertTrue(bodies[0].contains("Save button"))
        XCTAssertFalse(bodies[1].contains("Save button"))
    }

    func testToolOnlyReplyStillSaysWhatChanged() async {
        var step = 0
        let transport = MockTransport { _ in
            step += 1
            return step == 1
                ? (200, self.reply(content: nil, toolCalls: [("c1", "update_setup", #"{"layout":"thirds"}"#)]))
                : (200, self.reply(content: nil))
        }
        var form = SubjectFormState(subject: nil)
        let agent = SetupAgent(apiKey: { "sk" }, transport: transport, lookupApp: { _ in nil })
        agent.read = { form }
        agent.apply = { change in change(&form) }
        await agent.send("thirds please")
        XCTAssertEqual(agent.messages.last?.text, "Done: Layout → Thirds.")
        XCTAssertEqual(agent.messages.last?.changes, ["Layout → Thirds"])
    }

    func testGreetingMentionsMemoryForExistingSubjects() {
        let agent = SetupAgent(apiKey: { nil }, lookupApp: { _ in nil })
        agent.greet(name: "CS128", lastNote: "You were on MP3 tests.")
        XCTAssertTrue(agent.messages[0].text.contains("CS128"))
        XCTAssertTrue(agent.messages[0].text.contains("You were on MP3 tests."))
        XCTAssertFalse(agent.messages[0].text.lowercased().contains("lock in"))
        agent.greet(name: "CS128", lastNote: nil)
        XCTAssertEqual(agent.messages.count, 1)
    }
}
