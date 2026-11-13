import XCTest
@testable import Tofu

@MainActor private final class ChatFakeApps: AppUnblocking {
    var allowed: [String] = []
    var blockedAppsSummary: [String] = []
    func allowApp(named name: String) -> String {
        allowed.append(name)
        return "Allowed \(name) for this work block."
    }
}

@MainActor private final class ChatFakeSites: SiteVerdictReceiving {
    var allowed: [String] = []
    var closed: [String] = []
    var openTabsSummary: [String] = []
    func allowHost(_ host: String) { allowed.append(host) }
    func closeHost(_ host: String) { closed.append(host) }
}

/// Plays `responses` in order (the last one repeats).
private final class ResponseScript {
    private let responses: [(Int, Data)]
    private var index = 0
    init(_ responses: [(Int, Data)]) { self.responses = responses }
    func next() -> (Int, Data) {
        let response = responses[min(index, responses.count - 1)]
        index += 1
        return response
    }
}

/// Holds the request until `release()`, so a test can change the world while a reply is in flight.
private final class GatedTransport: HTTPTransport {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    let body: Data
    init(body: Data) { self.body = body }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.isWaiting = true
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class ChatAssistantTests: XCTestCase {
    // MARK: - Helpers

    /// One assistant wired to fake Chrome, a hand-fired timer, and a scripted transport.
    private struct Rig {
        let sites: ChatFakeSites
        let apps: ChatFakeApps
        let transport: MockTransport
        let assistant: ChatAssistant
        let timers: TimerBox
        let attention: CounterBox
        let key: KeyBox

        @MainActor func fire(_ index: Int = 0) { timers.items[index].fire() }
    }

    private final class TimerBox {
        var items: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
    }
    private final class CounterBox { var count = 0 }
    private final class KeyBox { var value: String? = "sk-test" }

    private func makeRig(_ responses: [(Int, Data)] = [(200, chatTextBody("ok"))]) -> Rig {
        let script = ResponseScript(responses)
        let mock = MockTransport { _ in script.next() }
        return makeRig(using: mock, mock: mock)
    }

    /// For transports the test scripts itself; `rig.transport` is then an unused placeholder.
    private func makeRig(using transport: HTTPTransport, mock: MockTransport = MockTransport { _ in (500, Data()) }) -> Rig {
        let timers = TimerBox()
        let attention = CounterBox()
        let key = KeyBox()
        let sites = ChatFakeSites()
        let apps = ChatFakeApps()
        let assistant = ChatAssistant(apiKey: { key.value }, transport: transport,
                                      scheduleTimeout: { delay, fire in timers.items.append((delay, fire)) })
        assistant.sites = sites
        assistant.apps = apps
        assistant.onNeedsAttention = { attention.count += 1 }
        return Rig(sites: sites, apps: apps, transport: mock, assistant: assistant, timers: timers, attention: attention, key: key)
    }

    private func requestJSON(_ rig: Rig, _ index: Int = 0) throws -> [String: Any] {
        let data = try XCTUnwrap(rig.transport.requests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func wireMessages(_ rig: Rig, _ index: Int = 0) throws -> [[String: Any]] {
        try XCTUnwrap(requestJSON(rig, index)["messages"] as? [[String: Any]])
    }

    private func texts(_ assistant: ChatAssistant) -> [String] { assistant.messages.map(\.text) }
    private func roles(_ assistant: ChatAssistant) -> [ChatMessage.Role] { assistant.messages.map(\.role) }

    private func question(_ host: String = "www.youtube.com", title: String = "Lo-fi beats", relevance: Double = 0.55) -> SiteQuestion {
        SiteQuestion(host: host, url: "https://\(host)/watch?v=1", title: title, relevance: relevance)
    }

    // MARK: - Session

    func testBeginSessionGreetsLocallyWithoutAnyRequest() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        XCTAssertEqual(rig.assistant.messages.count, 1)
        XCTAssertEqual(rig.assistant.messages[0].role, .assistant)
        XCTAssertEqual(rig.assistant.messages[0].text,
                       "Hi! You're locked in on CS128. I'm here if you get stuck — and I'll check in on sites that look off-topic.")
        XCTAssertTrue(rig.transport.requests.isEmpty)
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testDescriptionReachesTheModelAndTheGreetingStaysTheName() async throws {
        let rig = makeRig([(200, chatTextBody("On it."))])
        rig.assistant.beginSession(subject: "CS128", details: "Writing the problem sets")
        XCTAssertEqual(rig.assistant.messages[0].text,
                       "Hi! You're locked in on CS128. I'm here if you get stuck — and I'll check in on sites that look off-topic.")
        await rig.assistant.send("where do I start?")
        let system = try XCTUnwrap(try wireMessages(rig).first?["content"] as? String)
        XCTAssertTrue(system.contains("CS128. Writing the problem sets"))
    }

    func testBeginSessionResetsEarlierConversation() async {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        rig.assistant.beginSession(subject: "Calc II")
        XCTAssertEqual(rig.assistant.messages.count, 1)
        XCTAssertTrue(rig.assistant.messages[0].text.contains("Calc II"))
        // The same host can be asked about again in the new session.
        rig.assistant.askAboutSite(question(), subject: "Calc II")
        XCTAssertEqual(rig.assistant.messages.count, 2)
    }

    func testGreetAfterWakeAppendsWelcomeBackAndRequestsAttention() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.greetAfterWake()
        XCTAssertEqual(rig.assistant.messages.last?.role, .assistant)
        XCTAssertEqual(rig.assistant.messages.last?.text, "Welcome back! Still on CS128? What's next?")
        XCTAssertEqual(rig.attention.count, 1)
        XCTAssertTrue(rig.transport.requests.isEmpty)
    }

    func testEndSessionClearsTheConversation() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.endSession()
        XCTAssertTrue(rig.assistant.messages.isEmpty)
        XCTAssertFalse(rig.assistant.isThinking)
    }

    // MARK: - Request shape

    func testRequestHasModelToolsAuthAndSystemPromptWithSubjectAndOpenTabs() async throws {
        let rig = makeRig([(200, chatTextBody("Sure thing."))])
        rig.sites.openTabsSummary = ["piazza.com — CS128 Piazza", "youtube.com — Lo-fi beats"]
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("  can I check piazza?  ")

        XCTAssertEqual(rig.transport.requests.count, 1)
        let request = rig.transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let json = try requestJSON(rig)
        XCTAssertEqual(json["model"] as? String, "gpt-4.1-mini")
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, ["allow_site", "close_site", "allow_app"])

        let messages = try wireMessages(rig)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("CS128"))
        XCTAssertTrue(system.contains("piazza.com — CS128 Piazza"))
        XCTAssertTrue(system.contains("youtube.com — Lo-fi beats"))
        XCTAssertTrue(system.contains("allow_site") && system.contains("close_site") && system.contains("allow_app"))
        // The greeting is part of the history; the trimmed user text is last.
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "assistant", "user"])
        XCTAssertEqual(messages.last?["content"] as? String, "can I check piazza?")

        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .assistant])
        XCTAssertEqual(rig.assistant.messages.last?.text, "Sure thing.")
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testSystemPromptIsRebuiltOnEachRequest() async throws {
        let rig = makeRig([(200, chatTextBody("a")), (200, chatTextBody("b"))])
        rig.assistant.beginSession(subject: "CS128")
        rig.sites.openTabsSummary = ["a.com — First"]
        await rig.assistant.send("one")
        rig.sites.openTabsSummary = ["b.com — Second"]
        await rig.assistant.send("two")

        let first = try XCTUnwrap(try wireMessages(rig, 0).first?["content"] as? String)
        let second = try XCTUnwrap(try wireMessages(rig, 1).first?["content"] as? String)
        XCTAssertTrue(first.contains("a.com — First") && !first.contains("b.com"))
        XCTAssertTrue(second.contains("b.com — Second") && !second.contains("a.com"))
        // The second request carries the whole conversation so far.
        XCTAssertEqual(try wireMessages(rig, 1).map { $0["role"] as? String },
                       ["system", "assistant", "user", "assistant", "user"])
    }

    func testPendingQuestionsAppearInTheSystemPrompt() async throws {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("www.youtube.com", title: "Lo-fi beats", relevance: 0.55), subject: "CS128")
        await rig.assistant.send("it's for a lecture")

        let system = try XCTUnwrap(try wireMessages(rig).first?["content"] as? String)
        XCTAssertTrue(system.contains("youtube.com"))
        XCTAssertTrue(system.contains("Lo-fi beats"))
        XCTAssertTrue(system.contains("55%"))
        // The question the bot asked is in the history, so the model knows what the user is answering.
        let history = try wireMessages(rig)
        XCTAssertTrue((history[2]["content"] as? String ?? "").contains("How does it help with CS128?"))
    }

    // MARK: - Tool calls

    func testAllowToolCallAllowsHostPostsNoticeAndSendsResultBack() async throws {
        let rig = makeRig([
            (200, chatToolBody([("call_1", "allow_site", #"{"host":"www.YouTube.com","reason":"CS128 lecture 5"}"#)])),
            (200, chatTextBody("Nice, enjoy the lecture.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("youtube is for the CS128 lecture 5 recording")

        XCTAssertEqual(rig.sites.allowed, ["youtube.com"])
        XCTAssertTrue(rig.sites.closed.isEmpty)
        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .notice, .assistant])
        XCTAssertEqual(texts(rig.assistant)[2], "Allowed youtube.com")
        XCTAssertEqual(texts(rig.assistant)[3], "Nice, enjoy the lecture.")
        XCTAssertFalse(rig.assistant.isThinking)

        XCTAssertEqual(rig.transport.requests.count, 2)
        let second = try wireMessages(rig, 1)
        XCTAssertEqual(second.map { $0["role"] as? String }, ["system", "assistant", "user", "assistant", "tool"])
        let calls = try XCTUnwrap(second[3]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls[0]["id"] as? String, "call_1")
        XCTAssertEqual(second[4]["tool_call_id"] as? String, "call_1")
        XCTAssertTrue((second[4]["content"] as? String ?? "").contains("youtube.com"))
    }

    func testCloseToolCallClosesHostAndPostsNotice() async {
        let rig = makeRig([
            (200, chatToolBody([("call_9", "close_site", #"{"host":"reddit.com","reason":"entertainment"}"#)])),
            (200, chatTextBody("Closed it. Back to work!")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("just a quick scroll on reddit")

        XCTAssertEqual(rig.sites.closed, ["reddit.com"])
        XCTAssertTrue(rig.sites.allowed.isEmpty)
        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .notice, .assistant])
        XCTAssertEqual(texts(rig.assistant)[2], "Closed reddit.com")
        XCTAssertEqual(texts(rig.assistant)[3], "Closed it. Back to work!")
    }

    func testAllowAppToolUnblocksTheNamedApp() async throws {
        let rig = makeRig([
            (200, chatToolBody([("call_2", "allow_app", #"{"name":"Slack","reason":"class group chat"}"#)])),
            (200, chatTextBody("Slack's open.")),
        ])
        rig.apps.blockedAppsSummary = ["Slack — com.tinyspeck.slackmacgap"]
        rig.assistant.beginSession(subject: "MATH241")
        await rig.assistant.send("I need Slack, it's the MATH241 group chat")

        XCTAssertEqual(rig.apps.allowed, ["Slack"])
        XCTAssertEqual(texts(rig.assistant)[2], "Allowed Slack")
        let system = try XCTUnwrap(try wireMessages(rig).first?["content"] as? String)
        XCTAssertTrue(system.contains("Slack — com.tinyspeck.slackmacgap"))
        XCTAssertTrue(system.contains("allow_app"))
    }

    func testToolCallWithURLHostIsNormalized() async {
        let rig = makeRig([
            (200, chatToolBody([("c", "close_site", #"{"host":"https://WWW.Reddit.com/r/swift?x=1","reason":"fun"}"#)])),
            (200, chatTextBody("Done.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("reddit")
        XCTAssertEqual(rig.sites.closed, ["reddit.com"])
    }

    func testAllowSiteToolRefusesDistractionDomains() async throws {
        let rig = makeRig([
            (200, chatToolBody([("call_dist", "allow_site", #"{"host":"reddit.com","reason":"research"}"#)])),
            (200, chatTextBody("Reddit is blocked.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("Can I check reddit?")

        XCTAssertEqual(rig.sites.allowed, [])
        XCTAssertFalse(texts(rig.assistant).contains("Allowed reddit.com"))
    }

    func testSeveralToolCallsInOneReplyAllRun() async throws {
        let rig = makeRig([
            (200, chatToolBody([("a", "allow_site", #"{"host":"piazza.com","reason":"x"}"#),
                                ("b", "close_site", #"{"host":"reddit.com","reason":"y"}"#)])),
            (200, chatTextBody("Sorted.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("piazza yes reddit no")
        XCTAssertEqual(rig.sites.allowed, ["piazza.com"])
        XCTAssertEqual(rig.sites.closed, ["reddit.com"])
        let second = try wireMessages(rig, 1)
        XCTAssertEqual(second.map { $0["role"] as? String }, ["system", "assistant", "user", "assistant", "tool", "tool"])
    }

    func testToolCallWithoutHostOrUnknownToolDoesNothingButAnswersTheModel() async throws {
        let rig = makeRig([
            (200, chatToolBody([("a", "allow_site", #"{"reason":"x"}"#), ("b", "launch_missiles", "{}")])),
            (200, chatTextBody("Hm, let me rephrase.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("do something")
        XCTAssertTrue(rig.sites.allowed.isEmpty && rig.sites.closed.isEmpty)
        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .assistant])
        let second = try wireMessages(rig, 1)
        XCTAssertEqual(second.map { $0["role"] as? String }, ["system", "assistant", "user", "assistant", "tool", "tool"])
    }

    func testToolLoopStopsAfterThreeRoundsAndAsksForPlainText() async throws {
        let rig = makeRig([(200, chatToolBody([("loop", "allow_site", #"{"host":"a.com","reason":"x"}"#)]))])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("go")
        XCTAssertEqual(rig.transport.requests.count, 4)
        XCTAssertEqual(rig.sites.allowed.count, 3)
        XCTAssertNotNil(try requestJSON(rig, 2)["tools"])
        XCTAssertNil(try requestJSON(rig, 3)["tools"])
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testAssistantTextAlongsideToolCallIsShownBeforeTheNotice() async {
        let rig = makeRig([
            (200, chatToolBody([("a", "close_site", #"{"host":"reddit.com","reason":"fun"}"#)], content: "Nope, closing that.")),
            (200, chatTextBody("Back to it!")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("reddit?")
        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .assistant, .notice, .assistant])
        XCTAssertEqual(texts(rig.assistant)[2], "Nope, closing that.")
    }

    // MARK: - Failures

    func testNoKeyAnswersLocallyWithoutARequest() async {
        let rig = makeRig()
        rig.key.value = nil
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        XCTAssertTrue(rig.transport.requests.isEmpty)
        XCTAssertEqual(roles(rig.assistant), [.assistant, .user, .assistant])
        XCTAssertEqual(rig.assistant.messages.last?.text, "I can't think without an OpenAI API key — add one in Settings.")
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testBlankKeyCountsAsNoKey() async {
        let rig = makeRig()
        rig.key.value = "   "
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        XCTAssertTrue(rig.transport.requests.isEmpty)
    }

    func testKeySavedLaterAppliesImmediately() async {
        let rig = makeRig()
        rig.key.value = nil
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        rig.key.value = "sk-new"
        await rig.assistant.send("hello again")
        XCTAssertEqual(rig.transport.requests.count, 1)
        XCTAssertEqual(rig.transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer sk-new")
    }

    func testHTTPErrorAnswersWithSorry() async {
        let rig = makeRig([(500, MockTransport.json("{}"))])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        XCTAssertEqual(rig.assistant.messages.last?.role, .assistant)
        XCTAssertEqual(rig.assistant.messages.last?.text, "Sorry, I couldn't reach my brain (HTTP 500). Try again?")
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testBadAPIKeyReplyMentionsTheKey() async {
        let rig = makeRig([(401, MockTransport.json("{}"))])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        XCTAssertTrue(rig.assistant.messages.last?.text.contains("API key") == true)
    }

    func testOfflineAnswersWithSorry() async {
        struct Offline: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
        }
        let rig = makeRig(using: Offline())
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("hello?")
        let reply = rig.assistant.messages.last?.text ?? ""
        XCTAssertTrue(reply.hasPrefix("Sorry, I couldn't reach my brain ("))
        XCTAssertTrue(reply.hasSuffix("). Try again?"))
        XCTAssertFalse(rig.assistant.isThinking)
    }

    func testBlankMessageIsIgnored() async {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("   \n ")
        XCTAssertEqual(rig.assistant.messages.count, 1)
        XCTAssertTrue(rig.transport.requests.isEmpty)
    }

    // MARK: - Site questions

    func testAskAboutSiteAppendsLocalQuestionAndRequestsAttention() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("www.YouTube.com", title: "Lo-fi beats"), subject: "CS128")

        XCTAssertEqual(rig.assistant.messages.count, 2)
        XCTAssertEqual(rig.assistant.messages[1].role, .assistant)
        XCTAssertEqual(rig.assistant.messages[1].text, "You opened youtube.com (“Lo-fi beats”). How does it help with CS128?")
        XCTAssertEqual(rig.attention.count, 1)
        XCTAssertTrue(rig.transport.requests.isEmpty)
        XCTAssertEqual(rig.timers.items.count, 1)
        XCTAssertEqual(rig.timers.items[0].delay, 60)
    }

    func testAskAboutSiteWithoutTitleOmitsTheQuotes() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("youtube.com", title: "  "), subject: "CS128")
        XCTAssertEqual(rig.assistant.messages[1].text, "You opened youtube.com. How does it help with CS128?")
    }

    func testAskAboutSameHostTwiceIsIgnored() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("www.youtube.com"), subject: "CS128")
        rig.assistant.askAboutSite(question("youtube.com", title: "Other video"), subject: "CS128")
        XCTAssertEqual(rig.assistant.messages.count, 2)
        XCTAssertEqual(rig.attention.count, 1)
        XCTAssertEqual(rig.timers.items.count, 1)
    }

    func testAskAboutAnAlreadyDecidedHostIsIgnored() async {
        let rig = makeRig([
            (200, chatToolBody([("a", "allow_site", #"{"host":"youtube.com","reason":"x"}"#)])),
            (200, chatTextBody("Ok.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        await rig.assistant.send("can I check youtube for the lecture?")
        let before = rig.assistant.messages.count
        rig.assistant.askAboutSite(question("youtube.com"), subject: "CS128")
        XCTAssertEqual(rig.assistant.messages.count, before)
        XCTAssertEqual(rig.attention.count, 0)
    }

    func testDifferentHostsAreEachAskedAbout() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("youtube.com"), subject: "CS128")
        rig.assistant.askAboutSite(question("reddit.com", title: "swift"), subject: "CS128")
        XCTAssertEqual(rig.assistant.messages.count, 3)
        XCTAssertEqual(rig.attention.count, 2)
    }

    // MARK: - Voice popup hooks

    func testOnSiteAskedReplacesTheAttentionRequestAndCarriesTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_000)
        let assistant = ChatAssistant(apiKey: { "sk" }, transport: MockTransport { _ in (500, Data()) },
                                      clock: { start }, scheduleTimeout: { _, _ in })
        var attention = 0
        var asked: [ChatAssistant.PendingSite] = []
        assistant.onNeedsAttention = { attention += 1 }
        assistant.onSiteAsked = { asked.append($0) }
        assistant.beginSession(subject: "CS128")
        assistant.askAboutSite(question("www.youtube.com"), subject: "CS128")

        XCTAssertEqual(attention, 0)
        XCTAssertEqual(asked.map(\.host), ["youtube.com"])
        XCTAssertEqual(asked.first?.deadline, start.addingTimeInterval(60))
        XCTAssertEqual(assistant.pending, asked)
    }

    func testOnAssistantMessageSeesEveryBotLine() async {
        let rig = makeRig([(200, chatTextBody("Back to work!"))])
        var said: [String] = []
        rig.assistant.onAssistantMessage = { said.append($0) }
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("youtube.com", title: ""), subject: "CS128")
        await rig.assistant.send("nothing")
        XCTAssertEqual(said.count, 3)
        XCTAssertEqual(said[1], "You opened youtube.com. How does it help with CS128?")
        XCTAssertEqual(said[2], "Back to work!")
    }

    func testCloseSiteNowClosesClearsPendingAndBeatsTheTimeout() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("www.youtube.com"), subject: "CS128")
        rig.assistant.closeSiteNow("youtube.com")

        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
        XCTAssertTrue(rig.assistant.pending.isEmpty)
        XCTAssertEqual(rig.assistant.messages.last?.text, "Closed youtube.com")
        rig.fire()
        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
    }

    func testCloseSiteNowForAHostNotAskedAboutDoesNothing() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.closeSiteNow("reddit.com")
        XCTAssertTrue(rig.sites.closed.isEmpty)
        XCTAssertEqual(rig.assistant.messages.count, 1)
    }

    // MARK: - Timeout

    func testUnansweredQuestionClosesTheHostAfterTheTimeout() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question("www.youtube.com"), subject: "CS128")
        XCTAssertTrue(rig.sites.closed.isEmpty)

        rig.fire()

        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
        XCTAssertEqual(rig.assistant.messages.last?.role, .notice)
        XCTAssertEqual(rig.assistant.messages.last?.text, "Closed youtube.com — no answer in 1 minute")
    }

    func testTimeoutFiringTwiceClosesOnlyOnce() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        rig.fire()
        rig.fire()
        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
    }

    func testAnsweredHostIsNotClosedByTheTimeout() async {
        let rig = makeRig([
            (200, chatToolBody([("a", "allow_site", #"{"host":"youtube.com","reason":"lecture"}"#)])),
            (200, chatTextBody("Great.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        await rig.assistant.send("it's the CS128 lecture 5 recording")

        rig.fire()

        XCTAssertEqual(rig.sites.allowed, ["youtube.com"])
        XCTAssertTrue(rig.sites.closed.isEmpty)
        XCTAssertFalse(texts(rig.assistant).contains { $0.contains("no answer") })
    }

    func testClosedByTheBotThenTimeoutDoesNotCloseAgain() async {
        let rig = makeRig([
            (200, chatToolBody([("a", "close_site", #"{"host":"youtube.com","reason":"fun"}"#)])),
            (200, chatTextBody("Closed.")),
        ])
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        await rig.assistant.send("just vibes")
        rig.fire()
        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
    }

    func testEndSessionMakesTimeoutsNoOps() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        rig.assistant.endSession()

        rig.fire()

        XCTAssertTrue(rig.sites.closed.isEmpty)
        XCTAssertTrue(rig.assistant.messages.isEmpty)
    }

    func testNewSessionMakesOldTimeoutsNoOps() {
        let rig = makeRig()
        rig.assistant.beginSession(subject: "CS128")
        rig.assistant.askAboutSite(question(), subject: "CS128")
        rig.assistant.beginSession(subject: "Calc II")
        rig.assistant.askAboutSite(question(), subject: "Calc II")   // same host, new session

        rig.fire(0)   // the old session's timer
        XCTAssertTrue(rig.sites.closed.isEmpty)
        rig.fire(1)   // the new one
        XCTAssertEqual(rig.sites.closed, ["youtube.com"])
    }

    // MARK: - Stale replies

    func testReplyArrivingAfterANewSessionIsDropped() async throws {
        let gated = GatedTransport(body: chatToolBody([("a", "close_site", #"{"host":"reddit.com","reason":"fun"}"#)]))
        let rig = makeRig(using: gated)
        rig.assistant.beginSession(subject: "CS128")

        let sending = Task { await rig.assistant.send("reddit?") }
        for _ in 0..<200 where !gated.isWaiting { await Task.yield() }
        XCTAssertTrue(gated.isWaiting)
        XCTAssertTrue(rig.assistant.isThinking)

        rig.assistant.beginSession(subject: "Calc II")
        gated.release()
        await sending.value

        XCTAssertTrue(rig.sites.closed.isEmpty, "a tool call from a finished session must not run")
        XCTAssertEqual(rig.assistant.messages.count, 1)
        XCTAssertTrue(rig.assistant.messages[0].text.contains("Calc II"))
        XCTAssertFalse(rig.assistant.isThinking)
    }

    // MARK: - Host normalization

    func testNormalizeHost() {
        XCTAssertEqual(ChatAssistant.normalizeHost("WWW.YouTube.com"), "youtube.com")
        XCTAssertEqual(ChatAssistant.normalizeHost(" https://www.reddit.com/r/swift?x=1#top "), "reddit.com")
        XCTAssertEqual(ChatAssistant.normalizeHost("piazza.com:443"), "piazza.com")
        XCTAssertEqual(ChatAssistant.normalizeHost("docs.swift.org"), "docs.swift.org")
        XCTAssertEqual(ChatAssistant.normalizeHost(""), "")
    }
}
