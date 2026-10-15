import XCTest
import CryptoKit
@testable import Tofu

/// Fake Keychain: a box the auth reads and writes through its injected closures.
@MainActor private final class TokenBox {
    var token: String?
    func makeAuth(transport: MockTransport, now: @escaping () -> Date = Date.init) -> GoogleAuth {
        GoogleAuth(transport: transport, readToken: { [weak self] in self?.token },
                   writeToken: { [weak self] in self?.token = $0 }, now: now)
    }
}

private func tokenJSON(access: String = "at-1", expiresIn: Int = 3600, refresh: String? = nil) -> Data {
    var fields = [#""access_token": "\#(access)""#, #""expires_in": \#(expiresIn)"#]
    if let refresh { fields.append(#""refresh_token": "\#(refresh)""#) }
    return MockTransport.json("{" + fields.joined(separator: ",") + "}")
}

@MainActor final class GoogleAuthTests: XCTestCase {
    func testBeginAuthBuildsConsentURLWithPKCE() throws {
        let box = TokenBox()
        let auth = box.makeAuth(transport: MockTransport { _ in (200, Data()) })
        let pending = auth.beginAuth(redirectURI: "http://127.0.0.1:7777")
        let components = try XCTUnwrap(URLComponents(url: pending.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "accounts.google.com")
        XCTAssertEqual(components.path, "/o/oauth2/v2/auth")
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }
        XCTAssertEqual(query["client_id"], GoogleAuth.clientID)
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:7777")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["access_type"], "offline")
        XCTAssertEqual(query["prompt"], "consent")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], pending.state)
        XCTAssertEqual(query["scope"], GoogleAuth.scope)
        XCTAssertEqual(query["code_challenge"]?.isEmpty, false)
    }

    func testCallbackExchangesCodeAndStoresRefreshToken() async throws {
        let box = TokenBox()
        let transport = MockTransport { _ in (200, tokenJSON(refresh: "rt-1")) }
        let auth = box.makeAuth(transport: transport)
        let pending = auth.beginAuth(redirectURI: "http://127.0.0.1:7777")
        try await auth.handleCallback(code: "code-1", state: pending.state, redirectURI: "http://127.0.0.1:7777")
        XCTAssertEqual(box.token, "rt-1")
        XCTAssertTrue(auth.isConnected)
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=code-1"))
        XCTAssertTrue(body.contains("code_verifier="))
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://oauth2.googleapis.com/token")
    }

    func testCallbackRejectsWrongState() async {
        let box = TokenBox()
        let auth = box.makeAuth(transport: MockTransport { _ in (200, tokenJSON(refresh: "rt-1")) })
        _ = auth.beginAuth(redirectURI: "http://127.0.0.1:7777")
        do {
            try await auth.handleCallback(code: "c", state: "wrong", redirectURI: "http://127.0.0.1:7777")
            XCTFail("expected stateMismatch")
        } catch let error as GoogleAuthError { XCTAssertEqual(error, .stateMismatch) }
        catch { XCTFail("unexpected \(error)") }
    }

    func testCallbackWithoutRefreshTokenFails() async {
        let box = TokenBox()
        let auth = box.makeAuth(transport: MockTransport { _ in (200, tokenJSON()) })
        let pending = auth.beginAuth(redirectURI: "http://127.0.0.1:7777")
        do {
            try await auth.handleCallback(code: "c", state: pending.state, redirectURI: "http://127.0.0.1:7777")
            XCTFail("expected noRefreshToken")
        } catch let error as GoogleAuthError { XCTAssertEqual(error, .noRefreshToken) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertNil(box.token)
    }

    func testAccessTokenRefreshesOnceAndCaches() async throws {
        let box = TokenBox(); box.token = "rt-1"
        let transport = MockTransport { _ in (200, tokenJSON(access: "at-9")) }
        let auth = box.makeAuth(transport: transport)
        let first = try await auth.accessToken()
        let second = try await auth.accessToken()
        XCTAssertEqual(first, "at-9"); XCTAssertEqual(second, "at-9")
        XCTAssertEqual(transport.requests.count, 1, "second call must hit the in-memory cache")
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=rt-1"))
    }

    func testAccessTokenRefreshesWhenExpiryIsWithinSkew() async throws {
        let box = TokenBox(); box.token = "rt-1"
        var current = Date(timeIntervalSince1970: 1_000_000)
        var served = 0
        let transport = MockTransport { _ in served += 1; return (200, tokenJSON(access: "at-\(served)", expiresIn: 3600)) }
        let auth = box.makeAuth(transport: transport, now: { current })
        _ = try await auth.accessToken()
        current = current.addingTimeInterval(3600 - 30)   // inside the 60 s skew
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "at-2")
    }

    func testAccessTokenWhenNotConnectedThrows() async {
        let box = TokenBox()
        let auth = box.makeAuth(transport: MockTransport { _ in (200, Data()) })
        do { _ = try await auth.accessToken(); XCTFail("expected notConnected") }
        catch let error as GoogleAuthError { XCTAssertEqual(error, .notConnected) }
        catch { XCTFail("unexpected \(error)") }
    }

    func testRefreshWithRevokedTokenDisconnects() async {
        let box = TokenBox(); box.token = "rt-1"
        let transport = MockTransport { _ in (400, MockTransport.json(#"{"error": "invalid_grant"}"#)) }
        let auth = box.makeAuth(transport: transport)
        do { _ = try await auth.accessToken(); XCTFail("expected revoked") }
        catch let error as GoogleAuthError { XCTAssertEqual(error, .revoked) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertNil(box.token, "dead token must be deleted so Settings shows Connect")
        XCTAssertFalse(auth.isConnected)
    }

    func testTransientRefreshErrorKeepsToken() async {
        let box = TokenBox(); box.token = "rt-1"
        let transport = MockTransport { _ in (500, MockTransport.json(#"{"error": "internal"}"#)) }
        let auth = box.makeAuth(transport: transport)
        do { _ = try await auth.accessToken(); XCTFail("expected tokenEndpoint") }
        catch let error as GoogleAuthError { XCTAssertEqual(error, .tokenEndpoint("internal")) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(box.token, "rt-1")
    }

    func testDisconnectDeletesToken() {
        let box = TokenBox(); box.token = "rt-1"
        let auth = box.makeAuth(transport: MockTransport { _ in (200, Data()) })
        auth.disconnect()
        XCTAssertNil(box.token)
        XCTAssertFalse(auth.isConnected)
    }
}
