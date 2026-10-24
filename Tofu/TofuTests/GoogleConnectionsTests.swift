import XCTest
@testable import Tofu

/// Gmail (client, auth grant, models) and the Connections page's service states.
final class GmailClientTests: XCTestCase {
    private func makeClient(_ transport: MockTransport) -> GoogleClient {
        GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)
    }

    func testListMessageIDsEncodesTheSearch() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"messages": [{"id": "m1", "threadId": "t1"}, {"id": "m2", "threadId": "t2"}], "resultSizeEstimate": 2}"#)) }
        let ids = try await makeClient(transport).listMessageIDs(query: "is:unread category:primary newer_than:3d",
                                                                 maxResults: 10)
        XCTAssertEqual(ids, ["m1", "m2"])
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.host, "gmail.googleapis.com")
        XCTAssertEqual(url.path, "/gmail/v1/users/me/messages")
        XCTAssertTrue(url.absoluteString.contains("q=is:unread%20category:primary%20newer_than:3d"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("maxResults=10"))
    }

    func testListMessageIDsWithNoMessagesKeyIsEmpty() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"resultSizeEstimate": 0}"#)) }
        let ids = try await makeClient(transport).listMessageIDs(query: "x", maxResults: 10)
        XCTAssertEqual(ids, [])
    }

    func testMessageReadsMetadataHeaders() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"""
            {"id": "m1", "threadId": "t1", "snippet": "Don&#39;t forget &amp; submit", "internalDate": "1760000000000",
             "payload": {"headers": [{"name": "Subject", "value": "PS4 due Friday"},
                                     {"name": "From", "value": "\"Prof. Kim\" <kim@illinois.edu>"}]}}
            """#)) }
        let message = try await makeClient(transport).message(id: "m1")
        XCTAssertEqual(message.subject, "PS4 due Friday")
        XCTAssertEqual(message.senderName, "Prof. Kim")
        XCTAssertEqual(message.snippet, "Don't forget & submit")
        XCTAssertEqual(message.date, Date(timeIntervalSince1970: 1_760_000_000))
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/gmail/v1/users/me/messages/m1")
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("format=metadata"))
        XCTAssertTrue(query.contains("metadataHeaders=From"))
        XCTAssertTrue(query.contains("metadataHeaders=Subject"))
    }

    func testMessageWithoutHeadersStillDecodes() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "m1"}"#)) }
        let message = try await makeClient(transport).message(id: "m1")
        XCTAssertEqual(message, InboxMessage(id: "m1", from: "", subject: "", snippet: "", date: nil))
    }

    func testSenderName() {
        func name(_ from: String) -> String { InboxMessage(id: "x", from: from, subject: "", snippet: "", date: nil).senderName }
        XCTAssertEqual(name("Jane Doe <jane@x.edu>"), "Jane Doe")
        XCTAssertEqual(name("\"Doe, Jane\" <jane@x.edu>"), "Doe, Jane")
        XCTAssertEqual(name("<jane@x.edu>"), "jane@x.edu")
        XCTAssertEqual(name("jane@x.edu"), "jane@x.edu")
    }

    func testWebURLUsesTheAccountWhenKnown() {
        let message = InboxMessage(id: "18c2f", from: "", subject: "", snippet: "", date: nil)
        XCTAssertEqual(message.webURL(account: "ax@gmail.com")?.absoluteString,
                       "https://mail.google.com/mail/u/ax@gmail.com/#inbox/18c2f")
        XCTAssertEqual(message.webURL(account: nil)?.absoluteString, "https://mail.google.com/mail/u/0/#inbox/18c2f")
        XCTAssertEqual(message.webURL(account: "")?.absoluteString, "https://mail.google.com/mail/u/0/#inbox/18c2f")
    }

    func testInboxAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(InboxFormat.age(of: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(InboxFormat.age(of: now.addingTimeInterval(-12 * 60), now: now), "12m")
        XCTAssertEqual(InboxFormat.age(of: now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(InboxFormat.age(of: now.addingTimeInterval(-50 * 3600), now: now), "2d")
        XCTAssertEqual(InboxFormat.age(of: now.addingTimeInterval(120), now: now), "now")
    }

    func testOldSettingsTurnGmailOnByDefault() throws {
        let old = Data(#"{"displayName":"Ax","discordEnabled":true,"giveUpTemplate":"x","channelCache":{},"googleTasksSyncEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertTrue(settings.googleGmailEnabled)
        XCTAssertNil(settings.googleGrantedScopes)
        XCTAssertNil(settings.googleAccountEmail)
        XCTAssertFalse(settings.googleTasksSyncEnabled)
    }

    func testGmailSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.googleGmailEnabled = false
        settings.googleGrantedScopes = [GoogleAuth.tasksScope]
        settings.googleAccountEmail = "ax@gmail.com"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}

@MainActor final class GoogleGrantTests: XCTestCase {
    /// An unsigned ID token whose payload is `claims` (base64url, no padding).
    private func idToken(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).sig"
    }

    func testConsentAsksForGmailAndIdentity() throws {
        let auth = GoogleAuth(transport: MockTransport { _ in (200, Data()) }, readToken: { nil }, writeToken: { _ in })
        let url = auth.beginAuth(redirectURI: "http://127.0.0.1:1").url
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let scope = try XCTUnwrap(items.first { $0.name == "scope" }?.value)
        XCTAssertTrue(scope.contains(GoogleAuth.gmailScope))
        XCTAssertTrue(scope.split(separator: " ").contains("openid"))
        XCTAssertTrue(scope.split(separator: " ").contains("email"))
        XCTAssertEqual(items.first { $0.name == "include_granted_scopes" }?.value, "true")
    }

    func testSignInReportsScopesAndEmail() async throws {
        var token: String?
        let body = #"{"access_token": "at", "expires_in": 3600, "refresh_token": "rt", "#
            + #""scope": "\#(GoogleAuth.tasksScope) \#(GoogleAuth.gmailScope) openid", "#
            + #""id_token": "\#(idToken(#"{"sub":"1","email":"ax@gmail.com"}"#))"}"#
        let auth = GoogleAuth(transport: MockTransport { _ in (200, MockTransport.json(body)) },
                              readToken: { token }, writeToken: { token = $0 })
        var grants: [GoogleGrant] = []
        auth.onGrant = { grants.append($0) }
        let pending = auth.beginAuth(redirectURI: "http://127.0.0.1:1")
        try await auth.handleCallback(code: "c", state: pending.state, redirectURI: "http://127.0.0.1:1")
        XCTAssertEqual(grants, [GoogleGrant(scopes: [GoogleAuth.tasksScope, GoogleAuth.gmailScope, "openid"],
                                            email: "ax@gmail.com")])
    }

    func testRefreshOfAnOldTokenReportsNoGmail() async throws {
        let old = "\(GoogleAuth.tasksScope) \(GoogleAuth.calendarEventsScope) \(GoogleAuth.calendarScope)"
        let auth = GoogleAuth(transport: MockTransport { _ in
            (200, MockTransport.json(#"{"access_token": "at", "expires_in": 3600, "scope": "\#(old)"}"#))
        }, readToken: { "rt" }, writeToken: { _ in })
        var grants: [GoogleGrant] = []
        auth.onGrant = { grants.append($0) }
        _ = try await auth.accessToken()
        XCTAssertEqual(grants.count, 1)
        XCTAssertFalse(GoogleService.gmail.isGranted(by: grants[0].scopes))
        XCTAssertTrue(GoogleService.calendar.isGranted(by: grants[0].scopes))
        XCTAssertNil(grants[0].email)
    }

    func testResponseWithoutScopeReportsNothing() async throws {
        let auth = GoogleAuth(transport: MockTransport { _ in
            (200, MockTransport.json(#"{"access_token": "at", "expires_in": 3600}"#))
        }, readToken: { "rt" }, writeToken: { _ in })
        var called = false
        auth.onGrant = { _ in called = true }
        _ = try await auth.accessToken()
        XCTAssertFalse(called)
    }

    func testEmailFromIDToken() {
        XCTAssertEqual(GoogleAuth.email(fromIDToken: idToken(#"{"email":"a@b.co"}"#)), "a@b.co")
        XCTAssertNil(GoogleAuth.email(fromIDToken: idToken(#"{"sub":"1"}"#)))
        XCTAssertNil(GoogleAuth.email(fromIDToken: "garbage"))
    }
}

final class GoogleServiceStateTests: XCTestCase {
    private let all = [GoogleAuth.tasksScope, GoogleAuth.calendarEventsScope, GoogleAuth.calendarScope,
                       GoogleAuth.gmailScope]

    func testStates() {
        var settings = AppSettings()
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: false, settings: settings, granted: all), .disconnected)
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: true, settings: settings, granted: all), .on)
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: true, settings: settings,
                                             granted: [GoogleAuth.tasksScope]), .notGranted)
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: true, settings: settings, granted: nil), .on,
                       "unknown scopes (right after launch) are not flagged")
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: true, settings: settings, granted: all,
                                             gmailRefused: true), .unavailable)
        settings.googleGmailEnabled = false
        XCTAssertEqual(GoogleServiceState.of(.gmail, connected: true, settings: settings,
                                             granted: [GoogleAuth.tasksScope]), .off, "off wins over not granted")
    }

    func testCalendarIsOnWhileEitherSwitchIs() {
        var settings = AppSettings()
        settings.googleShowEventsEnabled = false
        XCTAssertTrue(GoogleService.calendar.isEnabled(in: settings))
        settings.googleSessionLogEnabled = false
        XCTAssertFalse(GoogleService.calendar.isEnabled(in: settings))
    }

    func testCalendarNeedsBothScopes() {
        XCTAssertFalse(GoogleService.calendar.isGranted(by: [GoogleAuth.calendarEventsScope]))
        XCTAssertTrue(GoogleService.calendar.isGranted(by: all))
    }

    func testOnlyNotGrantedStateSaysReconnect() {
        XCTAssertEqual(GoogleServiceState.notGranted.label, "Reconnect to enable")
        XCTAssertNil(GoogleServiceState.on.detail(for: .gmail))
        XCTAssertNotNil(GoogleServiceState.notGranted.detail(for: .gmail))
    }
}

final class GoogleDigestTests: XCTestCase {
    private func event(_ id: String, _ summary: String, start: String?, end: String?, day: String? = nil) -> GoogleEvent {
        GoogleEvent(id: id, summary: summary, start: GoogleEventTime(dateTime: start, date: day),
                    end: GoogleEventTime(dateTime: end, date: day))
    }

    private let now = GoogleEventTime.parseRFC3339("2026-10-15T12:00:00Z")!

    func testEmptyWhenNothingIsLeft() {
        let past = event("e1", "Morning lecture", start: "2026-10-15T09:00:00Z", end: "2026-10-15T09:50:00Z")
        XCTAssertEqual(GoogleDigest.promptBlock(events: [past], inbox: [], now: now), "")
    }

    func testRemainingEventsAndSubjectsAreCappedAndLabeledUntrusted() {
        let past = event("p", "Gone", start: "2026-10-15T09:00:00Z", end: "2026-10-15T09:50:00Z")
        let later = (1...7).map { event("e\($0)", "Event \($0)", start: "2026-10-15T13:00:00Z", end: "2026-10-15T14:00:00Z") }
        let allDay = event("d", "Career fair", start: nil, end: nil, day: "2026-10-15")
        let mail = (1...7).map { InboxMessage(id: "m\($0)", from: "Prof <p@x.edu>", subject: "Subject \($0)",
                                              snippet: "", date: nil) }
        let block = GoogleDigest.promptBlock(events: [past, allDay] + later, inbox: mail, now: now)
        XCTAssertTrue(block.contains("untrusted"))
        XCTAssertTrue(block.contains("Career fair"), "all-day events stay")
        XCTAssertFalse(block.contains("Gone"))
        XCTAssertTrue(block.contains("Event 4"))
        XCTAssertFalse(block.contains("Event 5"), "at most 5 events")
        XCTAssertTrue(block.contains("- Prof: Subject 5"))
        XCTAssertFalse(block.contains("Subject 6"), "at most 5 subjects")
    }
}

@MainActor final class ConnectionsWiringTests: XCTestCase {
    private final class TokenBox { var value: String? = "rt-1" }

    private func makeModel(api: FakeGoogleAPI, tokenBox: TokenBox,
                           transport: MockTransport = MockTransport { _ in (500, Data()) }) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectionsWiringTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = Store(fileURL: directory.appendingPathComponent("store.json"))
        let auth = GoogleAuth(transport: transport, readToken: { tokenBox.value }, writeToken: { tokenBox.value = $0 })
        let model = AppModel(store: store, engine: EngineHarness().engine, googleAuth: auth, googleAPI: api)
        addTeardownBlock { @MainActor in model.googleSync?.stop() }
        return model
    }

    func testGrantIsStoredAndOldTokensAskForReconnect() async throws {
        let old = "\(GoogleAuth.tasksScope) \(GoogleAuth.calendarEventsScope) \(GoogleAuth.calendarScope)"
        let transport = MockTransport { _ in
            (200, MockTransport.json(#"{"access_token": "at", "expires_in": 3600, "scope": "\#(old)"}"#))
        }
        let box = TokenBox()
        let model = try makeModel(api: FakeGoogleAPI(), tokenBox: box, transport: transport)
        XCTAssertEqual(model.googleState(of: .gmail), .on, "unknown until Google answers")
        _ = try await model.googleAuth.accessToken()
        XCTAssertEqual(model.data.settings.googleGrantedScopes, old.split(separator: " ").map(String.init).sorted())
        XCTAssertEqual(model.googleState(of: .gmail), .notGranted)
        XCTAssertEqual(model.googleState(of: .tasks), .on)
        XCTAssertTrue(model.googleNeedsReconnect)
        XCTAssertTrue(model.inboxMessages.isEmpty)

        model.updateSettings { $0.googleGmailEnabled = false }
        XCTAssertFalse(model.googleNeedsReconnect, "turning Gmail off drops the nag")

        model.disconnectGoogle()
        XCTAssertNil(model.data.settings.googleGrantedScopes)
        XCTAssertEqual(model.googleState(of: .tasks), .disconnected)
    }

    func testAgentContextHasTodaysMail() async throws {
        let api = FakeGoogleAPI()
        api.inboxIDs = ["m1"]
        api.inboxMessages = ["m1": InboxMessage(id: "m1", from: "Prof <p@x.edu>", subject: "Exam moved to Monday",
                                                snippet: "", date: nil)]
        let model = try makeModel(api: api, tokenBox: TokenBox())
        await model.googleSync?.syncNow()
        let deadline = Date().addingTimeInterval(2)
        while model.inboxMessages.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            await model.googleSync?.syncNow()
        }
        XCTAssertEqual(model.inboxMessages.map(\.id), ["m1"])
        XCTAssertTrue(model.agentContext().contains("Exam moved to Monday"))

        model.updateSettings { $0.googleGmailEnabled = false }
        XCTAssertFalse(model.agentContext().contains("Exam moved to Monday"))
    }
}
