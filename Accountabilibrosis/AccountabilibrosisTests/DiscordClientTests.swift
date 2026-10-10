import XCTest
@testable import Accountabilibrosis

/// Records every sleep the client asks for, without actually waiting.
private final class SleepSpy {
    private(set) var calls: [TimeInterval] = []
    func sleep(_ seconds: TimeInterval) async { calls.append(seconds) }
}

private let okBody = MockTransport.json("{}")
private let forbiddenBody = MockTransport.json(#"{"message": "Missing Access", "code": 50001}"#)

/// Text channels with the given ids, positions 0, 1, 2... in array order, no preferred names.
private func channelsJSON(_ ids: [String]) -> Data {
    let items = ids.enumerated().map { index, id in
        #"{"id": "\#(id)", "name": "chan-\#(id)", "type": 0, "position": \#(index)}"#
    }
    return MockTransport.json("[" + items.joined(separator: ",") + "]")
}

final class DiscordClientTests: XCTestCase {
    private func makeClient(_ transport: MockTransport, sleeper: SleepSpy = SleepSpy()) -> DiscordClient {
        DiscordClient(token: "test-token", transport: transport, sleep: { await sleeper.sleep($0) })
    }

    // MARK: - Requests

    func testMeSendsAuthAndUserAgentHeadersToUsersMe() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "42", "username": "lockbot", "bot": true}"#)) }
        let user = try await makeClient(transport).me()

        XCTAssertEqual(user, DiscordUser(id: "42", username: "lockbot"))
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://discord.com/api/v10/users/@me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "DiscordBot (accountabilibrosis, 1.0)")
        XCTAssertNil(request.httpBody)
    }

    func testGuildsAndChannelsPathsAndDecoding() async throws {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "Study Hall", "icon": null}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, MockTransport.json(#"[{"id": "10", "name": "general", "type": 0, "position": 0}]"#))
            default:
                return (404, MockTransport.json("{}"))
            }
        }
        let client = makeClient(transport)
        let guilds = try await client.guilds()
        let channels = try await client.channels(guildID: "1")

        XCTAssertEqual(guilds, [DiscordGuild(id: "1", name: "Study Hall")])
        XCTAssertEqual(channels, [DiscordChannel(id: "10", name: "general", type: 0, position: 0)])
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds", "GET /api/v10/guilds/1/channels"])
    }

    func testPostSendsContentWithMentionsDisabled() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "500"}"#)) }
        try await makeClient(transport).post(channelID: "77", content: "🔒 **Alex** is locked in on **CS128**")

        XCTAssertEqual(transport.log, ["POST /api/v10/channels/77/messages"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["content"] as? String, "🔒 **Alex** is locked in on **CS128**")
        let mentions = try XCTUnwrap(json["allowed_mentions"] as? [String: Any])
        let parse = try XCTUnwrap(mentions["parse"] as? [Any])
        XCTAssertTrue(parse.isEmpty)
        XCTAssertEqual(json.count, 2)
    }

    // MARK: - Errors

    func testNon2xxOnMeThrowsHTTPStatus() async {
        let transport = MockTransport { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized", "code": 0}"#)) }
        do {
            _ = try await makeClient(transport).me()
            XCTFail("expected DiscordError.http(401)")
        } catch {
            XCTAssertEqual(error as? DiscordError, .http(401))
        }
    }

    func testUndecodableBodyThrowsDecoding() async {
        let transport = MockTransport { _ in (200, MockTransport.json("not json")) }
        do {
            _ = try await makeClient(transport).me()
            XCTFail("expected DiscordError.decoding")
        } catch {
            XCTAssertEqual(error as? DiscordError, .decoding)
        }
    }

    // MARK: - 429 handling

    func testRateLimitSleepsRetryAfterThenRetriesOnce() async throws {
        var postCount = 0
        let transport = MockTransport { _ in
            postCount += 1
            if postCount == 1 {
                return (429, MockTransport.json(#"{"message": "You are being rate limited.", "retry_after": 1.5, "global": false}"#))
            }
            return (200, MockTransport.json("{}"))
        }
        let sleeper = SleepSpy()
        try await makeClient(transport, sleeper: sleeper).post(channelID: "7", content: "hi")

        XCTAssertEqual(sleeper.calls, [1.5])
        XCTAssertEqual(transport.log, ["POST /api/v10/channels/7/messages", "POST /api/v10/channels/7/messages"])
    }

    func testRateLimitTwiceGivesUpAfterOneRetry() async {
        let transport = MockTransport { _ in (429, MockTransport.json(#"{"retry_after": 0.25, "global": false}"#)) }
        let sleeper = SleepSpy()
        do {
            try await makeClient(transport, sleeper: sleeper).post(channelID: "7", content: "hi")
            XCTFail("expected DiscordError.http(429)")
        } catch {
            XCTAssertEqual(error as? DiscordError, .http(429))
        }
        XCTAssertEqual(sleeper.calls, [0.25])
        XCTAssertEqual(transport.requests.count, 2)
    }

    // MARK: - Broadcast

    func testForbiddenChannelFallsThroughToNextCandidate() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds": return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            case "/api/v10/guilds/1/channels": return (200, channelsJSON(["10", "11"]))
            case "/api/v10/channels/10/messages": return (403, forbiddenBody)
            case "/api/v10/channels/11/messages": return (200, okBody)
            default: return (404, okBody)
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: ["1": "11"], failedGuilds: []))
        XCTAssertEqual(transport.log, [
            "GET /api/v10/users/@me/guilds",
            "GET /api/v10/guilds/1/channels",
            "POST /api/v10/channels/10/messages",
            "POST /api/v10/channels/11/messages",
        ])
    }

    func testGuildWhereEveryCandidateFailsIsReportedWhileOtherGuildPosts() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "Locked"}, {"id": "2", "name": "Open"}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, channelsJSON(["101", "102", "103", "104", "105", "106", "107"]))
            case "/api/v10/guilds/2/channels":
                return (200, channelsJSON(["201"]))
            case "/api/v10/channels/201/messages":
                return (200, okBody)
            default:
                return (403, forbiddenBody)
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: ["2": "201"], failedGuilds: ["1"]))
        let guildOnePosts = transport.log.filter { $0.hasPrefix("POST /api/v10/channels/10") }
        XCTAssertEqual(guildOnePosts, [
            "POST /api/v10/channels/101/messages",
            "POST /api/v10/channels/102/messages",
            "POST /api/v10/channels/103/messages",
            "POST /api/v10/channels/104/messages",
            "POST /api/v10/channels/105/messages",
        ])
    }

    func testCachedChannelIsTriedFirst() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, MockTransport.json("""
                [{"id": "10", "name": "general", "type": 0, "position": 0},
                 {"id": "12", "name": "lock-in", "type": 0, "position": 1},
                 {"id": "11", "name": "random", "type": 0, "position": 5}]
                """))
            default:
                return (200, MockTransport.json("{}"))
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: ["1": "11"])

        XCTAssertEqual(report.posted, ["1": "11"])
        XCTAssertEqual(transport.log.last, "POST /api/v10/channels/11/messages")
        XCTAssertEqual(transport.log.filter { $0.hasPrefix("POST") }.count, 1)
    }

    func testChannelListFailureMarksGuildFailed() async {
        let transport = MockTransport { request in
            if request.url?.path == "/api/v10/users/@me/guilds" {
                return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            }
            return (403, MockTransport.json("{}"))
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: [:], failedGuilds: ["1"]))
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds", "GET /api/v10/guilds/1/channels"])
    }

    func testGuildsFailureGivesEmptyReportAndStops() async {
        let transport = MockTransport { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized"}"#)) }
        let report = await makeClient(transport).broadcast("hello", channelCache: ["1": "11"])

        XCTAssertEqual(report, DiscordPostReport())
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds"])
    }
}
