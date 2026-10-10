import XCTest
@testable import Accountabilibrosis

/// A DiscordAnnouncer wired to a MockTransport-backed DiscordClient, a FakeToaster and editable settings.
@MainActor private final class AnnouncerHarness {
    var settings = AppSettings(displayName: "Alex", discordEnabled: true)
    var token: String? = "test-token"
    private(set) var cacheUpdates: [[String: String]] = []
    private(set) var clientTokens: [String] = []
    let toaster = FakeToaster()
    let transport: MockTransport
    private(set) var announcer: DiscordAnnouncer!

    init(handler: @escaping (URLRequest) -> (Int, Data)) {
        let transport = MockTransport(handler: handler)
        self.transport = transport
        announcer = DiscordAnnouncer(
            token: { [weak self] in self?.token },
            settings: { [weak self] in self?.settings ?? AppSettings(discordEnabled: false) },
            onCacheUpdate: { [weak self] cache in self?.cacheUpdates.append(cache) },
            toaster: toaster,
            makeClient: { [weak self] token in
                self?.clientTokens.append(token)
                return DiscordClient(token: token, transport: transport, sleep: { _ in })
            })
    }
}

private let okBody = MockTransport.json("{}")

/// One guild "1" with text channels "10" (position 0) and "11" (position 1).
private func oneGuild(postStatus: @escaping (String) -> Int) -> (URLRequest) -> (Int, Data) {
    { request in
        let path = request.url?.path ?? ""
        switch path {
        case "/api/v10/users/@me/guilds":
            return (200, MockTransport.json(#"[{"id": "1", "name": "Study Hall"}]"#))
        case "/api/v10/guilds/1/channels":
            return (200, MockTransport.json("""
            [{"id": "10", "name": "general", "type": 0, "position": 0},
             {"id": "11", "name": "random", "type": 0, "position": 1}]
            """))
        default:
            let channelID = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            return (postStatus(channelID), okBody)
        }
    }
}

@MainActor
final class DiscordAnnouncerTests: XCTestCase {
    /// Polls `condition` every 10 ms for up to `timeout` seconds while the announcer's Task runs.
    private func waitUntil(timeout: TimeInterval = 1, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testDisabledSendsNothing() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.settings.discordEnabled = false

        h.announcer.announce("🔒 **Alex** is locked in on **CS128**")
        await waitUntil(timeout: 0.2) { false }

        XCTAssertEqual(h.clientTokens, [])
        XCTAssertEqual(h.transport.requests.count, 0)
        XCTAssertEqual(h.toaster.messages, [])
        XCTAssertEqual(h.cacheUpdates, [])
    }

    func testMissingOrBlankTokenSendsNothing() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.token = nil
        h.announcer.announce("hello")
        h.token = "   \n"
        h.announcer.announce("hello")
        await waitUntil(timeout: 0.2) { false }

        XCTAssertEqual(h.clientTokens, [])
        XCTAssertEqual(h.transport.requests.count, 0)
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testSuccessMergesPostedChannelIntoCache() async throws {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.token = "  test-token \n"
        h.settings.channelCache = ["9": "99"]

        h.announcer.announce("🔒 **Alex** is locked in on **CS128**")
        await waitUntil { !h.cacheUpdates.isEmpty }

        XCTAssertEqual(h.cacheUpdates, [["9": "99", "1": "10"]])
        XCTAssertEqual(h.toaster.messages, [])
        XCTAssertEqual(h.clientTokens, ["test-token"])
        XCTAssertEqual(h.transport.log, [
            "GET /api/v10/users/@me/guilds",
            "GET /api/v10/guilds/1/channels",
            "POST /api/v10/channels/10/messages",
        ])
        let post = try XCTUnwrap(h.transport.requests.last)
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        let body = try XCTUnwrap(post.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["content"] as? String, "🔒 **Alex** is locked in on **CS128**")
    }

    func testForbiddenChannelFallsThroughAndCachesTheWorkingOne() async {
        let h = AnnouncerHarness(handler: oneGuild { channelID in channelID == "10" ? 403 : 200 })

        h.announcer.announce("hello")
        await waitUntil { !h.cacheUpdates.isEmpty }

        XCTAssertEqual(h.cacheUpdates, [["1": "11"]])
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testEveryChannelFailingShowsOneToastAndKeepsCache() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 403 })
        h.settings.channelCache = ["1": "10"]

        h.announcer.announce("hello")
        await waitUntil { !h.toaster.messages.isEmpty }

        XCTAssertEqual(h.toaster.messages, ["Discord: couldn't post (check bot token/permissions)"])
        XCTAssertEqual(h.cacheUpdates, [])
        XCTAssertEqual(h.transport.log.filter { $0.hasPrefix("POST") }.count, 2)
    }

    func testBadTokenReturnsImmediatelyAndShowsOneToast() async {
        let h = AnnouncerHarness(handler: { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized"}"#)) })

        h.announcer.announce("hello")
        XCTAssertEqual(h.toaster.messages, [], "announce must not wait for the network")
        await waitUntil { !h.toaster.messages.isEmpty }

        XCTAssertEqual(h.toaster.messages, [DiscordAnnouncer.failureMessage])
        XCTAssertEqual(h.transport.log, ["GET /api/v10/users/@me/guilds"])
        XCTAssertEqual(h.cacheUpdates, [])
    }
}
