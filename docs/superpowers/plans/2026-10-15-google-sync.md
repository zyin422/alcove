# Google Tasks + Calendar Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two-way sync between Tofu's day plan and the user's default Google Tasks list, session logging to a dedicated "Tofu" Google Calendar, and a read-only view of today's calendar events.

**Architecture:** New `Tofu/Tofu/Engine/Google/` module: `GoogleAuth` (OAuth 2.0 PKCE with loopback redirect, refresh token in Keychain), `GoogleClient` (Tasks + Calendar REST over the shared `HTTPTransport` seam), `GoogleSync` (merge engine, 60s poll, mutation pushes). Pure merge/diff logic lives in `GoogleTaskMerge` so it tests without any I/O. `AppModel` owns the instances and routes mutations.

**Tech Stack:** Swift 5 / macOS 14, SwiftUI, Foundation + Network + CryptoKit only (no new dependencies), XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-15-google-sync-design.md` — read it before starting any task.

## Global Constraints

- Repo root for all commands: `/Users/axion66/coding/accountabilibrosis/Tofu` (the Xcode project dir).
- After creating or deleting ANY file, run `xcodegen generate` before building — the pbxproj is generated from `project.yml` directory globs. Never edit `project.pbxproj` by hand.
- Build/test command (full suite): `xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' -derivedDataPath build/DerivedData test 2>&1 | tail -20`. For one test class append `-only-testing:TofuTests/<ClassName>` before `test`... (exact order: `... -derivedDataPath build/DerivedData test -only-testing:TofuTests/GoogleAuthTests`).
- No new third-party dependencies. `import Network` and `import CryptoKit` are system frameworks and fine.
- Secrets: the Google refresh token goes ONLY in the Keychain (`Keychain.swift` wrapper), never in `store.json`. The OAuth client ID/secret constants are desktop-client values and are deliberately committed (RFC 8252: desktop client secrets are not confidential).
- All model/UI code is `@MainActor` (match `AppModel`). Doc comments in the codebase's style: one `///` line saying what/why, not how.
- Every new `AppSettings` / `Priority` field needs a codable fall-back so older `store.json` files still load (see the existing `init(from:)` pattern in `AppSettings.swift`).
- Commit after each task with a conventional message ending in:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## Review Focus

Failure modes the spec implies; each has its pinning test in the named task:

1. **Tasks API pagination** — Google returns `maxResults` (default 20) per page with `nextPageToken`; a mirror that reads one page silently drops tasks. Pinned in Task 4 (`testListTasksFollowsNextPageToken`).
2. **Old store files** — a `store.json` written before this feature must load with defaults, not crash. Pinned in Task 2 (`GoogleModelsTests`).
3. **Dead refresh token during a background poll** — `invalid_grant` must disconnect silently (Connect button reappears), not throw a toast every 60 s or crash. Pinned in Task 3 (`testRefreshWithRevokedTokenDisconnects`) and Task 7 (`testSyncAfterRevocationIsQuietNoop`).
4. **All-day events** — events with `date` and no `dateTime` must decode and render ("All day"), not crash sorting/formatting. Pinned in Task 5 (decode) and Task 8 (`testAllDayEventLabelAndSort`).
5. **Echo loop** — applying a remote pull to the plan must not be re-diffed and pushed back to Google (infinite insert loop). Pinned in Task 7 (`testApplyingRemotePlanPushesNothing`).

---

### Task 1: Shared HTTPTransport file

**Files:**
- Create: `Tofu/System/HTTPTransport.swift`
- Modify: `Tofu/Discord/DiscordClient.swift` (remove the moved declarations)

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol HTTPTransport { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }` and `struct URLSessionTransport: HTTPTransport`, used by every later task.

- [ ] **Step 1: Create the shared file**

Create `Tofu/System/HTTPTransport.swift` containing exactly the two declarations currently in `Tofu/Discord/DiscordClient.swift` (lines ~25–39):

```swift
import Foundation

/// Seam between HTTP clients (Discord, Google) and the network so tests can script responses.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport backed by `URLSession.shared`.
struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscordError.transport("Response was not HTTP")
        }
        return (data, http)
    }
}
```

- [ ] **Step 2: Remove the originals**

Delete the `HTTPTransport` protocol and `URLSessionTransport` struct from `DiscordClient.swift` (keep `DiscordError` where it is — the shared file references it).

- [ ] **Step 3: Regenerate project and run the full suite**

Run: `cd /Users/axion66/coding/accountabilibrosis/Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' -derivedDataPath build/DerivedData test 2>&1 | tail -5`
Expected: TEST SUCCEEDED (pure move; Discord tests prove nothing broke).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor: move HTTPTransport to a shared file

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Model groundwork — Priority.googleTaskID, AppSettings fields, Keychain coordinates

**Files:**
- Modify: `Tofu/Models/DayPlan.swift` (Priority)
- Modify: `Tofu/Models/AppSettings.swift`
- Modify: `Tofu/Persistence/Keychain.swift` (Secrets enum)
- Test: `TofuTests/GoogleModelsTests.swift` (create)

**Interfaces:**
- Produces: `Priority.googleTaskID: String?`; `AppSettings.googleTasksSyncEnabled/googleSessionLogEnabled/googleShowEventsEnabled: Bool` (all default `true`), `AppSettings.googleCalendarID: String?` (default nil); `Secrets.googleService = "com.tofu.google"`, `Secrets.googleAccount = "refresh-token"`.

- [ ] **Step 1: Write the failing tests**

Create `TofuTests/GoogleModelsTests.swift`:

```swift
import XCTest
@testable import Tofu

final class GoogleModelsTests: XCTestCase {
    func testPriorityWithoutGoogleTaskIDStillDecodes() throws {
        let old = Data(#"{"id":"\#(UUID().uuidString)","title":"Read ch. 3","isDone":false}"#.utf8)
        let priority = try JSONDecoder().decode(Priority.self, from: old)
        XCTAssertNil(priority.googleTaskID)
        XCTAssertEqual(priority.title, "Read ch. 3")
    }

    func testPriorityGoogleTaskIDRoundTrips() throws {
        var priority = Priority(title: "PS4")
        priority.googleTaskID = "gt-1"
        let decoded = try JSONDecoder().decode(Priority.self, from: JSONEncoder().encode(priority))
        XCTAssertEqual(decoded.googleTaskID, "gt-1")
    }

    func testOldSettingsDecodeWithGoogleDefaults() throws {
        let old = Data(#"{"displayName":"Ax","discordEnabled":true,"giveUpTemplate":"x","channelCache":{}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertTrue(settings.googleTasksSyncEnabled)
        XCTAssertTrue(settings.googleSessionLogEnabled)
        XCTAssertTrue(settings.googleShowEventsEnabled)
        XCTAssertNil(settings.googleCalendarID)
    }

    func testSettingsGoogleFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.googleTasksSyncEnabled = false
        settings.googleCalendarID = "cal-9"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.googleTasksSyncEnabled)
        XCTAssertEqual(decoded.googleCalendarID, "cal-9")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: the suite command with `-only-testing:TofuTests/GoogleModelsTests` (after `xcodegen generate`).
Expected: BUILD FAILS — `googleTaskID` / `googleTasksSyncEnabled` don't exist yet.

- [ ] **Step 3: Implement**

In `DayPlan.swift`, add to `Priority`: `var googleTaskID: String?` and extend the memberwise init with `googleTaskID: String? = nil` as the last parameter. `Priority` currently uses synthesized Codable — `String?` decodes as nil when absent, so no custom decoder is needed (verify: it has no explicit `init(from:)`).

In `AppSettings.swift`:
- Add the four stored properties and init parameters (defaults: `googleTasksSyncEnabled: Bool = true`, `googleSessionLogEnabled: Bool = true`, `googleShowEventsEnabled: Bool = true`, `googleCalendarID: String? = nil`).
- Extend the existing `init(from:)` with the same `decodeIfPresent ?? defaults.x` pattern used by every other field.

In `Keychain.swift`, add to `Secrets`:

```swift
    static let googleService = "com.tofu.google"
    static let googleAccount = "refresh-token"
```

- [ ] **Step 4: Run tests — expect PASS; also run the full suite once (AppSettings equality is used elsewhere)**

- [ ] **Step 5: Commit** — `feat: model groundwork for Google sync`

---

### Task 3: GoogleAuth — PKCE OAuth, token lifecycle, Keychain persistence

**Files:**
- Create: `Tofu/Engine/Google/GoogleAuth.swift`
- Test: `TofuTests/GoogleAuthTests.swift` (create)

**Interfaces:**
- Consumes: `HTTPTransport`, `Keychain`/`Secrets` (Task 1, 2).
- Produces (used by Tasks 4–10):

```swift
enum GoogleAuthError: Error, Equatable {
    case notConnected
    case stateMismatch
    case noRefreshToken
    /// Google said the refresh token is dead for good; the auth has already disconnected itself.
    case revoked
    case tokenEndpoint(String)
}

@MainActor final class GoogleAuth {
    static let clientID: String
    static let clientSecret: String
    static let scope: String
    struct PendingAuth { let url: URL; let state: String }
    init(transport: HTTPTransport = URLSessionTransport(),
         readToken: @escaping () -> String? = { Keychain.get(service: Secrets.googleService, account: Secrets.googleAccount) },
         writeToken: @escaping (String?) -> Void = { token in
             if let token { Keychain.set(token, service: Secrets.googleService, account: Secrets.googleAccount) }
             else { Keychain.delete(service: Secrets.googleService, account: Secrets.googleAccount) }
         },
         now: @escaping () -> Date = Date.init)
    var isConnected: Bool
    func beginAuth(redirectURI: String) -> PendingAuth
    func handleCallback(code: String, state: String, redirectURI: String) async throws
    func accessToken(forceRefresh: Bool = false) async throws -> String
    func disconnect()
}
```

- [ ] **Step 1: Write the failing tests**

Create `TofuTests/GoogleAuthTests.swift`:

```swift
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
        let auth = TokenBox().makeAuth(transport: MockTransport { _ in (200, Data()) })
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
        let auth = TokenBox().makeAuth(transport: MockTransport { _ in (200, tokenJSON(refresh: "rt-1")) })
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
        let auth = TokenBox().makeAuth(transport: MockTransport { _ in (200, Data()) })
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
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:TofuTests/GoogleAuthTests`) — build fails, type missing.

- [ ] **Step 3: Implement `Tofu/Engine/Google/GoogleAuth.swift`**

```swift
import CryptoKit
import Foundation

/// Why a Google auth step failed. `revoked` means the refresh token is dead for good and was dropped.
enum GoogleAuthError: Error, Equatable {
    case notConnected
    case stateMismatch
    case noRefreshToken
    case revoked
    case tokenEndpoint(String)
}

/// OAuth 2.0 PKCE for the shared Desktop client (reused from uiuc_collective_mind; its Google Cloud
/// project already has the Tasks and Calendar scopes). Desktop client secrets are not confidential
/// (RFC 8252); the flow is protected by PKCE. Refresh token in the Keychain, access token in memory.
@MainActor final class GoogleAuth {
    static let clientID = "727798165808-vkh1rujb994drot1gp3k5rk2jrmci23m.apps.googleusercontent.com"
    static let clientSecret = "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"
    static let scope = "https://www.googleapis.com/auth/tasks "
        + "https://www.googleapis.com/auth/calendar.events "
        + "https://www.googleapis.com/auth/calendar"
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let skew: TimeInterval = 60
    /// Google answers these only once a refresh token is dead for good (revoked, aged out of a
    /// Testing consent screen, or the client was edited); anything else is transient.
    private static let deadTokenErrors = ["invalid_grant", "unauthorized_client", "invalid_client", "deleted_client"]

    struct PendingAuth { let url: URL; let state: String }

    private let transport: HTTPTransport
    private let readToken: () -> String?
    private let writeToken: (String?) -> Void
    private let now: () -> Date
    private var state: String?
    private var verifier: String?
    private var accessTokenValue: String?
    private var accessTokenExpiry = Date.distantPast

    init(transport: HTTPTransport = URLSessionTransport(),
         readToken: @escaping () -> String? = { Keychain.get(service: Secrets.googleService, account: Secrets.googleAccount) },
         writeToken: @escaping (String?) -> Void = { token in
             if let token { Keychain.set(token, service: Secrets.googleService, account: Secrets.googleAccount) }
             else { Keychain.delete(service: Secrets.googleService, account: Secrets.googleAccount) }
         },
         now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.readToken = readToken
        self.writeToken = writeToken
        self.now = now
    }

    var isConnected: Bool { !(readToken() ?? "").isEmpty }

    /// Builds the consent URL and remembers the state and PKCE verifier for the callback.
    func beginAuth(redirectURI: String) -> PendingAuth {
        let state = Self.randomURLSafe(16)
        let verifier = Self.randomURLSafe(32)
        self.state = state
        self.verifier = verifier
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return PendingAuth(url: components.url!, state: state)
    }

    /// Exchanges the redirect's code for tokens. Google must return a refresh token (prompt=consent).
    func handleCallback(code: String, state: String, redirectURI: String) async throws {
        guard state == self.state, !state.isEmpty else { throw GoogleAuthError.stateMismatch }
        self.state = nil
        let verifier = self.verifier ?? ""
        self.verifier = nil
        let response = try await token(params: ["grant_type": "authorization_code", "code": code,
                                                "redirect_uri": redirectURI, "code_verifier": verifier])
        guard let refresh = response.refreshToken else { throw GoogleAuthError.noRefreshToken }
        writeToken(refresh)
        accessTokenValue = response.accessToken
        accessTokenExpiry = now().addingTimeInterval(TimeInterval(response.expiresIn))
    }

    /// A valid access token, refreshed through the stored refresh token when expired (60 s skew).
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let refresh = readToken(), !refresh.isEmpty else { throw GoogleAuthError.notConnected }
        if !forceRefresh, let cached = accessTokenValue, accessTokenExpiry.timeIntervalSince(now()) > Self.skew {
            return cached
        }
        let response: TokenResponse
        do {
            response = try await token(params: ["grant_type": "refresh_token", "refresh_token": refresh])
        } catch GoogleAuthError.tokenEndpoint(let code) where Self.deadTokenErrors.contains(code) {
            disconnect()
            throw GoogleAuthError.revoked
        }
        accessTokenValue = response.accessToken
        accessTokenExpiry = now().addingTimeInterval(TimeInterval(response.expiresIn))
        return response.accessToken
    }

    func disconnect() {
        writeToken(nil)
        accessTokenValue = nil
        accessTokenExpiry = .distantPast
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
        }
    }

    private struct TokenError: Decodable { let error: String? }

    private func token(params: [String: String]) async throws -> TokenResponse {
        var all = params
        all["client_id"] = Self.clientID
        all["client_secret"] = Self.clientSecret
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await transport.send(request)
        guard response.statusCode / 100 == 2,
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            let code = (try? JSONDecoder().decode(TokenError.self, from: data))?.error ?? "internal"
            throw GoogleAuthError.tokenEndpoint(code)
        }
        return decoded
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

Note: `import Security` may be needed for `SecRandomCopyBytes` (Keychain.swift already imports it; this file needs its own import).

- [ ] **Step 4: Run tests — PASS** (fix the 500-status test expectation if the error body decodes differently; the implementation maps any undecodable error body to `"internal"`).

- [ ] **Step 5: Commit** — `feat: Google OAuth with PKCE and Keychain-backed refresh token`

---

### Task 4: GoogleClient — Tasks + Calendar REST, pagination, 401 retry

**Files:**
- Create: `Tofu/Engine/Google/GoogleClient.swift`
- Test: `TofuTests/GoogleClientTests.swift` (create)

**Interfaces:**
- Consumes: `HTTPTransport` (Task 1). Token comes from an injected provider, NOT GoogleAuth directly, so tests don't need auth: `tokenProvider: (_ forceRefresh: Bool) async throws -> String`.
- Produces (used by Tasks 6–10):

```swift
enum GoogleError: Error, Equatable {
    case http(Int)
    case transport(String)
    case decoding
}

struct GoogleTask: Decodable, Equatable {
    let id: String
    var title: String?
    var status: String          // "needsAction" | "completed"
    var completed: String?      // RFC3339 timestamp, present when completed
    var due: String?
    var isDone: Bool { status == "completed" }
}

struct GoogleCalendarInfo: Decodable, Equatable {
    let id: String
    let summary: String?
    let selected: Bool?
}

struct GoogleEventTime: Decodable, Equatable {
    var dateTime: String?       // RFC3339 with offset, timed events
    var date: String?           // "2026-10-15", all-day events
    var parsed: Date? { dateTime.flatMap { GoogleEventTime.rfc3339.date(from: $0) } }
    static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct GoogleEvent: Decodable, Equatable, Identifiable {
    let id: String
    var summary: String?
    var start: GoogleEventTime
    var end: GoogleEventTime
}

protocol GoogleAPI {
    func listTasks() async throws -> [GoogleTask]
    func insertTask(title: String, due: String?) async throws -> GoogleTask
    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask
    func deleteTask(id: String) async throws
    func listCalendars() async throws -> [GoogleCalendarInfo]
    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo
    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws
    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent]
}

final class GoogleClient: GoogleAPI {
    init(tokenProvider: @escaping (Bool) async throws -> String,
         transport: HTTPTransport = URLSessionTransport())
}
```

- [ ] **Step 1: Write the failing tests**

Create `TofuTests/GoogleClientTests.swift`. Test list (write all of them; shapes follow `DiscordClientTests` — build the client with `GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)` unless the test says otherwise):

```swift
import XCTest
@testable import Tofu

final class GoogleClientTests: XCTestCase {
    private func makeClient(_ transport: MockTransport) -> GoogleClient {
        GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)
    }

    func testListTasksRequestsDefaultListWithCompletedAndHidden() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "t1", "title": "Read", "status": "needsAction"}]}"#)) }
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks, [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)])
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/tasks/v1/lists/@default/tasks")
        XCTAssertTrue(url.query?.contains("showCompleted=true") ?? false)
        XCTAssertTrue(url.query?.contains("showHidden=true") ?? false, "completed tasks are hidden without it")
        XCTAssertTrue(url.query?.contains("maxResults=100") ?? false)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer at-1")
    }

    func testListTasksFollowsNextPageToken() async throws {
        let transport = MockTransport { request in
            if request.url?.query?.contains("pageToken=p2") ?? false {
                return (200, MockTransport.json(#"{"items": [{"id": "t2", "status": "needsAction"}]}"#))
            }
            return (200, MockTransport.json(
                #"{"items": [{"id": "t1", "status": "needsAction"}], "nextPageToken": "p2"}"#))
        }
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks.map(\.id), ["t1", "t2"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testListTasksWithNoItemsKeyReturnsEmpty() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json("{}")) }   // Google omits "items" when empty
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks, [])
    }

    func testInsertTaskPostsTitleAndDue() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"id": "t9", "title": "PS4", "status": "needsAction"}"#)) }
        let task = try await makeClient(transport).insertTask(title: "PS4", due: "2026-10-15T00:00:00.000Z")
        XCTAssertEqual(task.id, "t9")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/tasks/v1/lists/@default/tasks")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["title": "PS4", "due": "2026-10-15T00:00:00.000Z"])
    }

    func testPatchTaskSendsOnlyGivenFields() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "t1", "status": "completed"}"#)) }
        _ = try await makeClient(transport).patchTask(id: "t1", title: nil, status: "completed")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/tasks/v1/lists/@default/tasks/t1")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["status": "completed"])
    }

    func testDeleteTask() async throws {
        let transport = MockTransport { _ in (204, Data()) }
        try await makeClient(transport).deleteTask(id: "t1")
        XCTAssertEqual(transport.log, ["DELETE /tasks/v1/lists/@default/tasks/t1"])
    }

    func testListCalendarsDecodesSelected() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "primary-id", "summary": "Me", "selected": true}, {"id": "tofu-id", "summary": "Tofu"}]}"#)) }
        let calendars = try await makeClient(transport).listCalendars()
        XCTAssertEqual(calendars.count, 2)
        XCTAssertEqual(calendars[0].selected, true)
        XCTAssertEqual(transport.requests.first?.url?.path, "/calendar/v3/users/me/calendarList")
    }

    func testInsertCalendar() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "cal-9", "summary": "Tofu"}"#)) }
        let calendar = try await makeClient(transport).insertCalendar(summary: "Tofu")
        XCTAssertEqual(calendar.id, "cal-9")
        XCTAssertEqual(transport.log, ["POST /calendar/v3/calendars"])
    }

    func testInsertEventBodyAndPath() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "ev-1"}"#)) }
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        try await makeClient(transport).insertEvent(calendarID: "cal-9", summary: "Focus: CS128",
                                                    description: "Goal 50 min", start: start,
                                                    end: start.addingTimeInterval(3000))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/calendar/v3/calendars/cal-9/events")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["summary"] as? String, "Focus: CS128")
        let startField = try XCTUnwrap(body["start"] as? [String: String])
        XCTAssertNotNil(startField["dateTime"])
    }

    func testListEventsWindowAndDecoding() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "e1", "summary": "Lecture", "start": {"dateTime": "2026-10-15T09:00:00-05:00"}, "end": {"dateTime": "2026-10-15T09:50:00-05:00"}}, {"id": "e2", "summary": "Fair", "start": {"date": "2026-10-15"}, "end": {"date": "2026-10-16"}}]}"#)) }
        let events = try await makeClient(transport).listEvents(calendarID: "a@b.com", from: Date(), to: Date())
        XCTAssertEqual(events.count, 2)
        XCTAssertNotNil(events[0].start.parsed)
        XCTAssertNil(events[1].start.parsed, "all-day events have no dateTime")
        XCTAssertEqual(events[1].start.date, "2026-10-15")
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertTrue(url.query?.contains("singleEvents=true") ?? false)
        XCTAssertTrue(url.query?.contains("timeMin=") ?? false)
        XCTAssertTrue(url.query?.contains("timeMax=") ?? false)
    }

    func testUnauthorizedForcesOneRefreshAndRetries() async throws {
        var tokens = ["at-old", "at-new"]
        var provided: [Bool] = []
        let transport = MockTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer at-new"
                ? (200, MockTransport.json("{}")) : (401, Data())
        }
        let client = GoogleClient(tokenProvider: { force in provided.append(force); return tokens.removeFirst() },
                                  transport: transport)
        _ = try await client.listTasks()
        XCTAssertEqual(provided, [false, true], "the retry must force a refresh")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSecondUnauthorizedThrowsHTTP401() async {
        let transport = MockTransport { _ in (401, Data()) }
        let client = GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)
        do { _ = try await client.listTasks(); XCTFail("expected http(401)") }
        catch let error as GoogleError { XCTAssertEqual(error, .http(401)) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(transport.requests.count, 2, "exactly one retry")
    }

    func testCalendarIDIsPercentEncodedInPath() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json("{}")) }
        _ = try await makeClient(transport).listEvents(calendarID: "en.usa#holiday@group.v.calendar.google.com",
                                                       from: Date(), to: Date())
        let path = transport.requests.first?.url?.absoluteString ?? ""
        XCTAssertTrue(path.contains("%23holiday"), "the # in calendar ids must be encoded, got \(path)")
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `Tofu/Engine/Google/GoogleClient.swift`**

Key implementation notes (write the full client; the models are in the Interfaces block above):

```swift
import Foundation

// ... GoogleError, GoogleTask, GoogleCalendarInfo, GoogleEventTime, GoogleEvent, GoogleAPI
// exactly as declared in the plan's Interfaces block for this task ...

/// Minimal REST client for the Google Tasks and Calendar APIs (spec §2 of the Google sync design).
final class GoogleClient: GoogleAPI {
    private static let tasksBase = "https://tasks.googleapis.com/tasks/v1"
    private static let calendarBase = "https://www.googleapis.com/calendar/v3"
    private let tokenProvider: (Bool) async throws -> String
    private let transport: HTTPTransport

    init(tokenProvider: @escaping (Bool) async throws -> String,
         transport: HTTPTransport = URLSessionTransport()) {
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    func listTasks() async throws -> [GoogleTask] {
        struct Page: Decodable { let items: [GoogleTask]?; let nextPageToken: String? }
        var all: [GoogleTask] = []
        var pageToken: String?
        repeat {
            var query = "showCompleted=true&showHidden=true&maxResults=100"
            if let pageToken { query += "&pageToken=\(pageToken)" }
            let page: Page = try await get("\(Self.tasksBase)/lists/@default/tasks?\(query)")
            all.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    func insertTask(title: String, due: String?) async throws -> GoogleTask {
        var body: [String: String] = ["title": title]
        if let due { body["due"] = due }
        return try await send("POST", "\(Self.tasksBase)/lists/@default/tasks", json: body)
    }

    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask {
        var body: [String: String] = [:]
        if let title { body["title"] = title }
        if let status { body["status"] = status }
        return try await send("PATCH", "\(Self.tasksBase)/lists/@default/tasks/\(id)", json: body)
    }

    func deleteTask(id: String) async throws {
        _ = try await raw("DELETE", "\(Self.tasksBase)/lists/@default/tasks/\(id)", body: nil)
    }

    func listCalendars() async throws -> [GoogleCalendarInfo] {
        struct Page: Decodable { let items: [GoogleCalendarInfo]? }
        let page: Page = try await get("\(Self.calendarBase)/users/me/calendarList")
        return page.items ?? []
    }

    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo {
        try await send("POST", "\(Self.calendarBase)/calendars", json: ["summary": summary])
    }

    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws {
        struct Ignored: Decodable {}
        let body: [String: Any] = [
            "summary": summary,
            "description": description,
            "start": ["dateTime": GoogleEventTime.rfc3339.string(from: start)],
            "end": ["dateTime": GoogleEventTime.rfc3339.string(from: end)],
        ]
        let _: Ignored = try await send("POST", "\(Self.calendarBase)/calendars/\(encode(calendarID))/events", jsonAny: body)
    }

    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        struct Page: Decodable { let items: [GoogleEvent]? }
        let timeMin = encode(GoogleEventTime.rfc3339.string(from: from))
        let timeMax = encode(GoogleEventTime.rfc3339.string(from: to))
        let page: Page = try await get("\(Self.calendarBase)/calendars/\(encode(calendarID))/events"
            + "?singleEvents=true&orderBy=startTime&maxResults=50&timeMin=\(timeMin)&timeMax=\(timeMax)")
        return page.items ?? []
    }

    // MARK: - Plumbing

    /// Percent-encodes calendar ids (they contain # and @) and RFC3339 timestamps (+ and :).
    private func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters:
            CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#+&=?"))) ?? string
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        try await decode(raw("GET", url, body: nil))
    }

    private func send<T: Decodable>(_ method: String, _ url: String, json: [String: String]) async throws -> T {
        try await decode(raw(method, url, body: try JSONSerialization.data(withJSONObject: json)))
    }

    private func send<T: Decodable>(_ method: String, _ url: String, jsonAny: [String: Any]) async throws -> T {
        try await decode(raw(method, url, body: try JSONSerialization.data(withJSONObject: jsonAny)))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw GoogleError.decoding }
        return decoded
    }

    /// One request with a fresh access token; a 401 forces one token refresh and one retry.
    private func raw(_ method: String, _ url: String, body: Data?) async throws -> Data {
        var attempt = 0
        while true {
            let token = try await tokenProvider(attempt > 0)
            guard let requestURL = URL(string: url) else { throw GoogleError.transport("bad url") }
            var request = URLRequest(url: requestURL)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let data: Data
            let response: HTTPURLResponse
            do { (data, response) = try await transport.send(request) }
            catch { throw GoogleError.transport(error.localizedDescription) }
            if response.statusCode == 401, attempt == 0 { attempt += 1; continue }
            guard response.statusCode / 100 == 2 else { throw GoogleError.http(response.statusCode) }
            return data
        }
    }
}
```

Adjust the `Ignored` decode for empty bodies: `deleteTask` uses `raw` directly (204, no decode); `insertEvent` decodes `{"id": ...}` fine with an empty struct only if `decode` tolerates it — an empty struct decodes from any JSON object, which `{"id": "ev-1"}` is. A truly empty body (`Data()`) on 204 never goes through `decode`.

- [ ] **Step 4: Run tests — PASS.**

- [ ] **Step 5: Commit** — `feat: Google Tasks and Calendar REST client`

---

### Task 5: LoopbackServer — localhost redirect catcher

**Files:**
- Create: `Tofu/Engine/Google/LoopbackServer.swift`
- Test: `TofuTests/LoopbackServerTests.swift` (create)

**Interfaces:**
- Produces (used by Task 9):

```swift
/// One-shot localhost HTTP listener for the OAuth redirect (http://127.0.0.1:<port>).
final class LoopbackServer {
    /// Starts listening on an ephemeral port; returns it. `onCallback` fires on the main queue once.
    func start(onCallback: @escaping @Sendable (_ code: String?, _ state: String?) -> Void) throws -> UInt16
    func stop()
    /// code/state from "GET /?code=...&state=... HTTP/1.1"; pure, for tests.
    static func parse(requestLine: String) -> (code: String?, state: String?)
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Tofu

final class LoopbackServerTests: XCTestCase {
    func testParseRequestLine() {
        let parsed = LoopbackServer.parse(requestLine: "GET /?state=xyz&code=4%2Fabc HTTP/1.1")
        XCTAssertEqual(parsed.code, "4/abc")
        XCTAssertEqual(parsed.state, "xyz")
    }

    func testParseWithoutQueryGivesNils() {
        let parsed = LoopbackServer.parse(requestLine: "GET /favicon.ico HTTP/1.1")
        XCTAssertNil(parsed.code)
        XCTAssertNil(parsed.state)
    }

    func testRealRequestHitsCallbackAndGetsResponsePage() async throws {
        let server = LoopbackServer()
        let expectation = expectation(description: "callback")
        nonisolated(unsafe) var received: (String?, String?) = (nil, nil)
        let port = try server.start { code, state in
            received = (code, state)
            expectation.fulfill()
        }
        defer { server.stop() }
        let url = URL(string: "http://127.0.0.1:\(port)/?code=abc&state=xyz")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("connected") ?? false)
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(received.0, "abc")
        XCTAssertEqual(received.1, "xyz")
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement with the Network framework**

```swift
import Foundation
import Network

/// One-shot localhost HTTP listener for the OAuth redirect. Reads the request line, answers with a
/// small "you're connected" page, and reports the code and state exactly once.
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tofu.google.loopback")

    func start(onCallback: @escaping @Sendable (String?, String?) -> Void) throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                let line = request.components(separatedBy: "\r\n").first ?? ""
                let (code, state) = Self.parse(requestLine: line)
                let page = "<html><body style=\"font-family:-apple-system\"><h2>Tofu is connected to Google.</h2>You can close this tab.</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                if code != nil || state != nil {
                    DispatchQueue.main.async { onCallback(code, state) }
                }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        // The port is assigned asynchronously; wait briefly for it.
        for _ in 0..<100 {
            if let port = listener.port?.rawValue, port > 0 { return port }
            Thread.sleep(forTimeInterval: 0.01)
        }
        listener.cancel()
        throw GoogleError.transport("loopback listener got no port")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    static func parse(requestLine: String) -> (code: String?, state: String?) {
        guard let pathPart = requestLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathPart)) else { return (nil, nil) }
        let items = components.queryItems ?? []
        return (items.first { $0.name == "code" }?.value, items.first { $0.name == "state" }?.value)
    }
}
```

If the port-wait loop proves flaky, switch to `listener.stateUpdateHandler` + a semaphore; keep the 1 s cap.

- [ ] **Step 4: Run tests — PASS.**

- [ ] **Step 5: Commit** — `feat: loopback listener for the Google OAuth redirect`

---

### Task 6: GoogleTaskMerge — pure pull-merge and local diff

**Files:**
- Create: `Tofu/Engine/Google/GoogleTaskMerge.swift`
- Test: `TofuTests/GoogleTaskMergeTests.swift` (create)

**Interfaces:**
- Consumes: `Priority` (Task 2), `GoogleTask` (Task 4), `DayKey` (existing).
- Produces (used by Task 7):

```swift
struct Retitle: Equatable { var id: String; var title: String }

/// What changed locally between two versions of today's plan, in Google terms.
struct PlanDiff: Equatable {
    var inserts: [Priority] = []     // new local priorities with no googleTaskID yet
    var completes: [String] = []     // googleTaskIDs whose priority flipped to done
    var reopens: [String] = []       // flipped back to not done
    var deletes: [String] = []       // linked priorities that were removed
    var retitles: [Retitle] = []
    var isEmpty: Bool { inserts.isEmpty && completes.isEmpty && reopens.isEmpty && deletes.isEmpty && retitles.isEmpty }
}

enum GoogleTaskMerge {
    /// Remote wins (spec §3). Returns today's new priority list and the local-only ones to insert.
    static func apply(remote: [GoogleTask], to local: [Priority], now: Date = Date(),
                      calendar: Calendar = .current) -> (priorities: [Priority], toInsert: [Priority])
    static func diff(from old: [Priority], to new: [Priority]) -> PlanDiff
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Tofu

private func task(_ id: String, _ title: String, done: Bool = false, completed: String? = nil) -> GoogleTask {
    GoogleTask(id: id, title: title, status: done ? "completed" : "needsAction", completed: completed, due: nil)
}

final class GoogleTaskMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)   // fixed instant

    // MARK: apply (pull; remote wins)

    func testRemoteTasksBecomePriorities() {
        let (priorities, toInsert) = GoogleTaskMerge.apply(remote: [task("t1", "Read"), task("t2", "PS4")], to: [], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Read", "PS4"])
        XCTAssertEqual(priorities.map(\.googleTaskID), ["t1", "t2"])
        XCTAssertTrue(toInsert.isEmpty)
    }

    func testLinkedLocalKeepsIdentityAndSubjectButFollowsRemote() {
        let subjectID = UUID()
        var linked = Priority(title: "Old title", subjectID: subjectID)
        linked.googleTaskID = "t1"
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "New title", done: true,
                                                                  completed: GoogleEventTime.rfc3339.string(from: now))],
                                                    to: [linked], now: now)
        XCTAssertEqual(priorities.count, 1)
        XCTAssertEqual(priorities[0].id, linked.id, "UUID survives so UI selection/links hold")
        XCTAssertEqual(priorities[0].subjectID, subjectID)
        XCTAssertEqual(priorities[0].title, "New title")
        XCTAssertTrue(priorities[0].isDone)
    }

    func testTaskCompletedBeforeTodayIsIgnored() {
        let yesterday = GoogleEventTime.rfc3339.string(from: now.addingTimeInterval(-86_400 * 2))
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "Done long ago", done: true, completed: yesterday)],
                                                    to: [], now: now)
        XCTAssertTrue(priorities.isEmpty)
    }

    func testTaskCompletedTodayShowsAsDone() {
        let completed = GoogleEventTime.rfc3339.string(from: now.addingTimeInterval(-60))
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "Just finished", done: true, completed: completed)],
                                                    to: [], now: now)
        XCTAssertEqual(priorities.map(\.isDone), [true])
    }

    func testUnlinkedLocalSurvivesAndIsQueuedForInsert() {
        let local = Priority(title: "Added in Tofu")
        let (priorities, toInsert) = GoogleTaskMerge.apply(remote: [task("t1", "Remote")], to: [local], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Added in Tofu", "Remote"], "locals keep their place, new remotes append")
        XCTAssertEqual(toInsert.map(\.id), [local.id])
    }

    func testLinkedLocalGoneFromRemoteIsDroppedUnlessDone() {
        var gone = Priority(title: "Deleted in Google"); gone.googleTaskID = "t-gone"
        var keptDone = Priority(title: "Finished earlier", isDone: true); keptDone.googleTaskID = "t-done-gone"
        let (priorities, _) = GoogleTaskMerge.apply(remote: [], to: [gone, keptDone], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Finished earlier"], "done ones stay as the day's record")
    }

    func testUntitledRemoteTaskGetsPlaceholder() {
        let (priorities, _) = GoogleTaskMerge.apply(remote: [GoogleTask(id: "t1", title: nil, status: "needsAction",
                                                                        completed: nil, due: nil)], to: [], now: now)
        XCTAssertEqual(priorities.map(\.title), ["(untitled)"])
    }

    // MARK: diff (local push)

    func testDiffFindsInsertCompleteReopenDeleteRetitle() {
        var done = Priority(title: "A"); done.googleTaskID = "tA"
        var reopened = Priority(title: "B", isDone: true); reopened.googleTaskID = "tB"
        var deleted = Priority(title: "C"); deleted.googleTaskID = "tC"
        var renamed = Priority(title: "D"); renamed.googleTaskID = "tD"
        let old = [done, reopened, deleted, renamed]
        var newDone = done; newDone.isDone = true
        var newReopened = reopened; newReopened.isDone = false
        var newRenamed = renamed; newRenamed.title = "D v2"
        let added = Priority(title: "E")
        let diff = GoogleTaskMerge.diff(from: old, to: [newDone, newReopened, newRenamed, added])
        XCTAssertEqual(diff.inserts.map(\.id), [added.id])
        XCTAssertEqual(diff.completes, ["tA"])
        XCTAssertEqual(diff.reopens, ["tB"])
        XCTAssertEqual(diff.deletes, ["tC"])
        XCTAssertEqual(diff.retitles, [Retitle(id: "tD", title: "D v2")])
    }

    func testDiffOfIdenticalPlansIsEmpty() {
        var linked = Priority(title: "A"); linked.googleTaskID = "tA"
        XCTAssertTrue(GoogleTaskMerge.diff(from: [linked], to: [linked]).isEmpty)
    }

    func testDiffIgnoresUnlinkedRemovals() {
        let unlinked = Priority(title: "Never synced")
        XCTAssertTrue(GoogleTaskMerge.diff(from: [unlinked], to: []).isEmpty,
                      "nothing to delete in Google for a priority that was never there")
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `Tofu/Engine/Google/GoogleTaskMerge.swift`**

Rules, in order, for `apply` (remote wins — spec §3):
1. Partition remote: keep tasks that are not done, or done with a `completed` timestamp whose `DayKey.key(for:)` equals `DayKey.key(for: now)`; drop the rest.
2. Walk `local` in order: unlinked priorities are kept as-is (and collected into `toInsert`); linked priorities whose task is kept get title (`task.title ?? "(untitled)"`) and `isDone` from the task (UUID and `subjectID` preserved); linked priorities whose task is gone are kept only when `isDone`.
3. Append remaining kept remote tasks (ones that matched no local priority) in remote order as new `Priority(title:..., isDone: task.isDone, googleTaskID: task.id)` — `Priority` has no `isDone` in its init's first positions; use `Priority(title: t, subjectID: nil, isDone: task.isDone)` then set `googleTaskID` (check the actual init signature from Task 2).

`diff` matches by `Priority.id` (UUID): inserts = in `new` but not `old` and `googleTaskID == nil`; for pairs present in both with a `googleTaskID`: `isDone` false→true ⇒ completes, true→false ⇒ reopens, title change ⇒ retitles; linked priorities in `old` missing from `new` ⇒ deletes.

- [ ] **Step 4: Run tests — PASS.**

- [ ] **Step 5: Commit** — `feat: pure merge and diff logic for the Google task mirror`

---

### Task 7: GoogleSync — the engine

**Files:**
- Create: `Tofu/Engine/Google/GoogleSync.swift`
- Test: `TofuTests/GoogleSyncTests.swift` (create)

**Interfaces:**
- Consumes: `GoogleAPI` (Task 4), `GoogleTaskMerge`/`PlanDiff` (Task 6), `GoogleAuthError` (Task 3), `AppSettings`, `DayPlan`, `Session`, `DayKey`.
- Produces (used by Tasks 8–10):

```swift
/// Polls Google and routes local mutations (spec §3–§4). Owned by AppModel; all closures read it.
@Observable @MainActor final class GoogleSync {
    init(api: GoogleAPI,
         settings: @escaping () -> AppSettings,
         isConnected: @escaping () -> Bool,
         plan: @escaping () -> DayPlan,                     // today's (DayKey.key(now)) plan
         applyPlan: @escaping (DayPlan) -> Void,            // write-through that must NOT re-enter planChanged
         saveCalendarID: @escaping (String?) -> Void,
         onError: @escaping (String) -> Void = { _ in },
         now: @escaping () -> Date = Date.init)
    private(set) var todayEvents: [GoogleEvent]             // sorted by start
    func start()                                            // 60 s timer + didBecomeActive observer
    func stop()
    func syncNow() async
    /// AppModel calls this after every mutation of today's plan; remote applies are guarded internally.
    func planChanged(from old: DayPlan, to new: DayPlan)
    /// AppModel calls this for every finalized session; eligibility is checked here.
    func sessionEnded(_ session: Session)
    nonisolated static func shouldLog(_ session: Session) -> Bool
    nonisolated static func eventSummary(for session: Session) -> String       // "Focus: CS128"
    nonisolated static func eventDescription(for session: Session) -> String
}
```

- [ ] **Step 1: Write the failing tests**

Create `TofuTests/GoogleSyncTests.swift` with a scripted `FakeGoogleAPI` that records calls and serves canned data:

```swift
import XCTest
@testable import Tofu

/// Scripted GoogleAPI: records every call, serves canned data, can fail on command.
@MainActor final class FakeGoogleAPI: GoogleAPI {
    var tasks: [GoogleTask] = []
    var calendars: [GoogleCalendarInfo] = []
    var events: [String: [GoogleEvent]] = [:]      // calendarID -> events
    var error: Error?
    private(set) var log: [String] = []
    private var nextID = 100

    func listTasks() async throws -> [GoogleTask] { try bump("listTasks"); return tasks }
    func insertTask(title: String, due: String?) async throws -> GoogleTask {
        try bump("insertTask \(title)")
        nextID += 1
        let task = GoogleTask(id: "t\(nextID)", title: title, status: "needsAction", completed: nil, due: due)
        tasks.append(task)
        return task
    }
    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask {
        try bump("patchTask \(id) \(title ?? "-") \(status ?? "-")")
        return GoogleTask(id: id, title: title, status: status ?? "needsAction", completed: nil, due: nil)
    }
    func deleteTask(id: String) async throws { try bump("deleteTask \(id)") }
    func listCalendars() async throws -> [GoogleCalendarInfo] { try bump("listCalendars"); return calendars }
    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo {
        try bump("insertCalendar \(summary)")
        return GoogleCalendarInfo(id: "tofu-cal", summary: summary, selected: nil)
    }
    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws {
        try bump("insertEvent \(calendarID) \(summary)")
    }
    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        try bump("listEvents \(calendarID)")
        return events[calendarID] ?? []
    }
    private func bump(_ entry: String) throws { log.append(entry); if let error { throw error } }
}

@MainActor final class GoogleSyncTests: XCTestCase {
    private var api = FakeGoogleAPI()
    private var settings = AppSettings()
    private var plan = DayPlan(day: DayKey.key(for: Date()))
    private var savedCalendarID: String??
    private var errors: [String] = []

    private func makeSync(connected: Bool = true) -> GoogleSync {
        GoogleSync(api: api,
                   settings: { self.settings },
                   isConnected: { connected },
                   plan: { self.plan },
                   applyPlan: { self.plan = $0 },
                   saveCalendarID: { self.savedCalendarID = $0; self.settings.googleCalendarID = $0 },
                   onError: { self.errors.append($0) })
    }

    func testSyncPullsTasksIntoPlan() async {
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        await makeSync().syncNow()
        XCTAssertEqual(plan.priorities.map(\.title), ["Read"])
        XCTAssertEqual(plan.priorities.map(\.googleTaskID), ["t1"])
    }

    func testSyncInsertsUnlinkedPrioritiesAndLinksThem() async {
        plan.priorities = [Priority(title: "Added locally")]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        await makeSync().syncNow()
        XCTAssertTrue(api.log.contains { $0.hasPrefix("insertTask Added locally") })
        XCTAssertNotNil(plan.priorities.first?.googleTaskID, "the returned id must be linked back")
    }

    func testApplyingRemotePlanPushesNothing() async {
        api.tasks = [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)]
        settings.googleSessionLogEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        // applyPlan in AppModel routes through updatePlan, which reports back to planChanged. Simulate that:
        let old = plan
        await sync.syncNow()
        sync.planChanged(from: old, to: plan)   // must be ignored while/after a remote apply of the same content
        await Task.yield()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertTask") }, "remote apply must not echo back: \(api.log)")
    }

    func testPlanChangedPushesDiff() async {
        var linked = Priority(title: "A"); linked.googleTaskID = "tA"
        let old = DayPlan(day: plan.day, priorities: [linked])
        var newDone = linked; newDone.isDone = true
        let new = DayPlan(day: plan.day, priorities: [newDone])
        let sync = makeSync()
        sync.planChanged(from: old, to: new)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(api.log, ["patchTask tA - completed"])
    }

    func testPlanChangedWhenTasksSyncOffDoesNothing() async {
        settings.googleTasksSyncEnabled = false
        let old = DayPlan(day: plan.day, priorities: [])
        let new = DayPlan(day: plan.day, priorities: [Priority(title: "X")])
        makeSync().planChanged(from: old, to: new)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(api.log.isEmpty)
    }

    func testSessionEndedQueuesAndSyncPushesEvent() async {
        api.calendars = []
        settings.googleTasksSyncEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        let start = Date().addingTimeInterval(-1800)
        var session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 30), start: start)
        session.end = Date(); session.outcome = .completed
        sync.sessionEnded(session)
        await sync.syncNow()
        XCTAssertTrue(api.log.contains("insertCalendar Tofu"), "no Tofu calendar yet, create it: \(api.log)")
        XCTAssertTrue(api.log.contains("insertEvent tofu-cal Focus: CS128"))
        XCTAssertEqual(savedCalendarID, "tofu-cal")
        api.log.removeAll()
        await sync.syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertEvent") }, "pushed once, not again")
    }

    func testExistingTofuCalendarIsReusedNotRecreated() async {
        api.calendars = [GoogleCalendarInfo(id: "cal-old", summary: "Tofu", selected: nil)]
        settings.googleTasksSyncEnabled = false
        settings.googleShowEventsEnabled = false
        let sync = makeSync()
        var session = Session(subjectID: UUID(), subjectName: "X", mode: .open, start: Date().addingTimeInterval(-600))
        session.end = Date(); session.outcome = .completed
        sync.sessionEnded(session)
        await sync.syncNow()
        XCTAssertFalse(api.log.contains { $0.hasPrefix("insertCalendar") })
        XCTAssertTrue(api.log.contains("insertEvent cal-old Focus: X"))
    }

    func testEventsPulledFromSelectedCalendarsExcludingTofu() async {
        settings.googleTasksSyncEnabled = false
        settings.googleSessionLogEnabled = false
        settings.googleCalendarID = "tofu-cal"
        api.calendars = [GoogleCalendarInfo(id: "primary", summary: "Me", selected: true),
                         GoogleCalendarInfo(id: "tofu-cal", summary: "Tofu", selected: true),
                         GoogleCalendarInfo(id: "ignored", summary: "Off", selected: false)]
        api.events = ["primary": [GoogleEvent(id: "e1", summary: "Lecture",
                                              start: GoogleEventTime(dateTime: "2026-10-15T09:00:00-05:00", date: nil),
                                              end: GoogleEventTime(dateTime: "2026-10-15T09:50:00-05:00", date: nil))]]
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertEqual(sync.todayEvents.map(\.id), ["e1"])
        XCTAssertTrue(api.log.contains("listEvents primary"))
        XCTAssertFalse(api.log.contains("listEvents tofu-cal"))
        XCTAssertFalse(api.log.contains("listEvents ignored"))
    }

    func testSyncWhenDisconnectedDoesNothing() async {
        api.tasks = [GoogleTask(id: "t1", title: "X", status: "needsAction", completed: nil, due: nil)]
        await makeSync(connected: false).syncNow()
        XCTAssertTrue(api.log.isEmpty)
    }

    func testSyncAfterRevocationIsQuietNoop() async {
        api.error = GoogleAuthError.revoked
        let sync = makeSync()
        await sync.syncNow()
        XCTAssertTrue(errors.isEmpty, "revocation flips the UI to Connect; no toast storm")
    }

    func testTransientErrorReportsOnceNotEveryCycle() async {
        api.error = GoogleError.http(500)
        let sync = makeSync()
        await sync.syncNow()
        await sync.syncNow()
        XCTAssertEqual(errors.count, 1, "only the transition into failure is reported")
        api.error = nil
        await sync.syncNow()
        api.error = GoogleError.http(500)
        await sync.syncNow()
        XCTAssertEqual(errors.count, 2, "a new failure after a success is reported again")
    }

    // MARK: shouldLog / event text

    func testShouldLogRules() {
        let start = Date().addingTimeInterval(-3600)
        var completed = Session(subjectID: UUID(), subjectName: "A", mode: .open, start: start)
        completed.end = start.addingTimeInterval(60); completed.outcome = .completed
        XCTAssertTrue(GoogleSync.shouldLog(completed))
        var shortBail = completed; shortBail.outcome = .bailed; shortBail.end = start.addingTimeInterval(200)
        XCTAssertFalse(GoogleSync.shouldLog(shortBail), "bailed under 5 minutes")
        var longBail = completed; longBail.outcome = .bailed; longBail.end = start.addingTimeInterval(400)
        XCTAssertTrue(GoogleSync.shouldLog(longBail))
        var demo = completed; demo.isDemo = true
        XCTAssertFalse(GoogleSync.shouldLog(demo))
        var interrupted = completed; interrupted.outcome = .interrupted
        XCTAssertFalse(GoogleSync.shouldLog(interrupted))
        var unfinished = completed; unfinished.end = nil; unfinished.outcome = nil
        XCTAssertFalse(GoogleSync.shouldLog(unfinished))
    }

    func testEventTexts() {
        let start = Date().addingTimeInterval(-3000)
        var session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 50), start: start,
                              blockedAttempts: 3, closedTabs: 2)
        session.end = start.addingTimeInterval(3000); session.outcome = .completed
        XCTAssertEqual(GoogleSync.eventSummary(for: session), "Focus: CS128")
        let description = GoogleSync.eventDescription(for: session)
        XCTAssertTrue(description.contains("50 min goal"))
        XCTAssertTrue(description.contains("completed"))
        XCTAssertTrue(description.contains("3 blocked"))
        XCTAssertTrue(description.contains("2 tabs closed"))
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `Tofu/Engine/Google/GoogleSync.swift`**

Structure (fill in fully):

```swift
import AppKit
import Foundation
import Observation

@Observable @MainActor final class GoogleSync {
    private let api: GoogleAPI
    private let settings: () -> AppSettings
    private let isConnected: () -> Bool
    private let plan: () -> DayPlan
    private let applyPlan: (DayPlan) -> Void
    private let saveCalendarID: (String?) -> Void
    private let onError: (String) -> Void
    private let now: () -> Date

    private(set) var todayEvents: [GoogleEvent] = []
    @ObservationIgnored private var pendingSessions: [Session] = []
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var isApplyingRemote = false
    @ObservationIgnored private var lastCycleFailed = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    // init as in the Interfaces block ...

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        Task { await syncNow() }
    }

    func stop() { /* invalidate timer, remove observer */ }

    func syncNow() async {
        let current = settings()
        guard isConnected(), !isSyncing,
              current.googleTasksSyncEnabled || current.googleSessionLogEnabled || current.googleShowEventsEnabled
        else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            if current.googleTasksSyncEnabled { try await syncTasks() }
            if current.googleSessionLogEnabled { try await pushPendingSessions() }
            if current.googleShowEventsEnabled { try await pullEvents() }
            lastCycleFailed = false
        } catch GoogleAuthError.revoked {
            // The auth already dropped the token; the UI shows Connect again. Stay quiet.
        } catch {
            if !lastCycleFailed { onError("Google sync failed: \(error)") }
            lastCycleFailed = true
        }
    }

    private func syncTasks() async throws {
        let remote = try await api.listTasks()
        var (priorities, toInsert) = GoogleTaskMerge.apply(remote: remote, to: plan().priorities, now: now())
        for pending in toInsert {
            let due = GoogleEventTime.rfc3339.string(from: Calendar.current.startOfDay(for: now()))
            let inserted = try await api.insertTask(title: pending.title, due: due)
            if let index = priorities.firstIndex(where: { $0.id == pending.id }) {
                priorities[index].googleTaskID = inserted.id
            }
        }
        var updated = plan()
        updated.priorities = priorities
        isApplyingRemote = true
        applyPlan(updated)
        isApplyingRemote = false
    }

    func planChanged(from old: DayPlan, to new: DayPlan) {
        guard !isApplyingRemote, isConnected(), settings().googleTasksSyncEnabled else { return }
        let diff = GoogleTaskMerge.diff(from: old.priorities, to: new.priorities)
        guard !diff.isEmpty else { return }
        Task { await push(diff) }
    }

    private func push(_ diff: PlanDiff) async {
        do {
            for priority in diff.inserts {
                let due = GoogleEventTime.rfc3339.string(from: Calendar.current.startOfDay(for: now()))
                let inserted = try await api.insertTask(title: priority.title, due: due)
                var updated = plan()
                if let index = updated.priorities.firstIndex(where: { $0.id == priority.id }) {
                    updated.priorities[index].googleTaskID = inserted.id
                    isApplyingRemote = true
                    applyPlan(updated)
                    isApplyingRemote = false
                }
            }
            for id in diff.completes { _ = try await api.patchTask(id: id, title: nil, status: "completed") }
            for id in diff.reopens { _ = try await api.patchTask(id: id, title: nil, status: "needsAction") }
            for id in diff.deletes { try await api.deleteTask(id: id) }
            for retitle in diff.retitles { _ = try await api.patchTask(id: retitle.id, title: retitle.title, status: nil) }
        } catch GoogleAuthError.revoked {
        } catch {
            if !lastCycleFailed { onError("Google sync failed: \(error)") }
            lastCycleFailed = true
        }
    }

    func sessionEnded(_ session: Session) {
        guard isConnected(), settings().googleSessionLogEnabled, Self.shouldLog(session) else { return }
        pendingSessions.append(session)
        Task { await syncNow() }
    }

    private func pushPendingSessions() async throws {
        guard !pendingSessions.isEmpty else { return }
        let calendarID = try await tofuCalendarID()
        while let session = pendingSessions.first {
            try await api.insertEvent(calendarID: calendarID,
                                      summary: Self.eventSummary(for: session),
                                      description: Self.eventDescription(for: session),
                                      start: session.start, end: session.end ?? now())
            pendingSessions.removeFirst()
        }
    }

    /// The cached "Tofu" calendar id, found by summary or created on first use (spec §4).
    private func tofuCalendarID() async throws -> String {
        if let cached = settings().googleCalendarID { return cached }
        let calendars = try await api.listCalendars()
        let id: String
        if let existing = calendars.first(where: { $0.summary == "Tofu" }) { id = existing.id }
        else { id = try await api.insertCalendar(summary: "Tofu").id }
        saveCalendarID(id)
        return id
    }

    private func pullEvents() async throws {
        let calendars = try await api.listCalendars()
        let tofuID = settings().googleCalendarID
        // Calendar days are midnight-to-midnight local (spec §4), unlike DayKey's 4 AM window.
        let dayStart = Calendar.current.startOfDay(for: now())
        let dayEnd = dayStart.addingTimeInterval(86_400)
        var all: [GoogleEvent] = []
        for calendar in calendars where calendar.selected == true && calendar.id != tofuID {
            all.append(contentsOf: try await api.listEvents(calendarID: calendar.id, from: dayStart, to: dayEnd))
        }
        todayEvents = all.sorted { GoogleEventFormat.sortKey($0, calendar: .current) < GoogleEventFormat.sortKey($1, calendar: .current) }
    }

    nonisolated static func shouldLog(_ session: Session) -> Bool {
        guard !session.isDemo, session.end != nil else { return false }
        switch session.outcome {
        case .completed: return true
        case .bailed: return session.duration >= 300
        default: return false
        }
    }

    nonisolated static func eventSummary(for session: Session) -> String { "Focus: \(session.subjectName)" }

    nonisolated static func eventDescription(for session: Session) -> String {
        var parts: [String] = []
        if let goal = session.mode.goalMinutes { parts.append("\(goal) min goal") } else { parts.append("open session") }
        parts.append(session.outcome == .completed ? "completed" : "bailed")
        if session.blockedAttempts > 0 { parts.append("\(session.blockedAttempts) blocked attempts") }
        if session.closedTabs > 0 { parts.append("\(session.closedTabs) tabs closed") }
        return parts.joined(separator: " · ")
    }
}
```

`GoogleEventFormat.sortKey` doesn't exist until Task 8 — for THIS task, sort inline instead: timed events by `start.parsed`, all-day events first at `dayStart`:

```swift
        todayEvents = all.sorted { ($0.start.parsed ?? dayStart) < ($1.start.parsed ?? dayStart) }
```

(Task 8 may leave this inline sort as is.)

One sequencing trap: `testApplyingRemotePlanPushesNothing` calls `planChanged` AFTER `syncNow` returned, when `isApplyingRemote` is already false. The guard that makes it pass is `diff.isEmpty` — after a pull, the applied plan and the re-read plan are identical, so the diff is empty. The `isApplyingRemote` flag protects the synchronous window where AppModel's `updatePlan` reports back during `applyPlan`. Both guards are needed; keep both.

- [ ] **Step 4: Run tests — PASS.** The two timing-dependent tests use short sleeps; if flaky, replace the sleeps with awaiting an expectation fulfilled from the fake's log (poll with `Task.yield()` in a loop up to 2 s).

- [ ] **Step 5: Commit** — `feat: Google sync engine with task mirror, session logging and event pull`

---

### Task 8: GoogleEventFormat — display helpers

**Files:**
- Create: `Tofu/Engine/Google/GoogleEventFormat.swift`
- Test: `TofuTests/GoogleEventFormatTests.swift` (create)

**Interfaces:**
- Consumes: `GoogleEvent`/`GoogleEventTime` (Task 4).
- Produces (used by Task 10): `GoogleEventFormat.timeLabel(_ event: GoogleEvent) -> String` and `GoogleEventFormat.sortKey(_ event: GoogleEvent, calendar: Calendar) -> Date`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Tofu

final class GoogleEventFormatTests: XCTestCase {
    private func timed(_ startISO: String, _ endISO: String) -> GoogleEvent {
        GoogleEvent(id: "e", summary: "X",
                    start: GoogleEventTime(dateTime: startISO, date: nil),
                    end: GoogleEventTime(dateTime: endISO, date: nil))
    }

    func testTimedEventLabelShowsStartAndEnd() {
        let event = timed("2026-10-15T09:00:00-05:00", "2026-10-15T09:50:00-05:00")
        let label = GoogleEventFormat.timeLabel(event)
        XCTAssertTrue(label.contains("–"), "label joins start and end: \(label)")
        XCTAssertFalse(label.isEmpty)
    }

    func testAllDayEventLabelAndSort() {
        let allDay = GoogleEvent(id: "e2", summary: "Career fair",
                                 start: GoogleEventTime(dateTime: nil, date: "2026-10-15"),
                                 end: GoogleEventTime(dateTime: nil, date: "2026-10-16"))
        XCTAssertEqual(GoogleEventFormat.timeLabel(allDay), "All day")
        let sortKey = GoogleEventFormat.sortKey(allDay, calendar: .current)
        let timedKey = GoogleEventFormat.sortKey(timed("2026-10-15T09:00:00-05:00", "2026-10-15T10:00:00-05:00"),
                                                 calendar: .current)
        XCTAssertLessThanOrEqual(sortKey, timedKey, "all-day events sort to the top")
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Read-only display helpers for pulled calendar events (spec §4: no editing, time + title only).
enum GoogleEventFormat {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// "9:00 – 9:50 AM" for timed events, "All day" for date-only ones.
    static func timeLabel(_ event: GoogleEvent) -> String {
        guard let start = event.start.parsed else { return "All day" }
        let startText = time.string(from: start)
        guard let end = event.end.parsed else { return startText }
        return "\(startText) – \(time.string(from: end))"
    }

    /// Timed events by start; all-day events at the very start of the day so they list first.
    static func sortKey(_ event: GoogleEvent, calendar: Calendar = .current) -> Date {
        event.start.parsed ?? calendar.startOfDay(for: Date())
    }
}
```

Then, in `GoogleSync.pullEvents` (Task 7), replace the inline sort with `GoogleEventFormat.sortKey` if Task 7 left it inline; both sides must compile together.

- [ ] **Step 4: Run tests — PASS** (also re-run `GoogleSyncTests`).

- [ ] **Step 5: Commit** — `feat: display formatting for pulled calendar events`

---

### Task 9: AppModel wiring — ownership, mutation routing, connect flow

**Files:**
- Modify: `Tofu/App/AppModel.swift`
- Test: `TofuTests/GoogleWiringTests.swift` (create)

**Interfaces:**
- Consumes: everything above.
- Produces (used by Task 10):

```swift
// On AppModel:
let googleAuth: GoogleAuth
private(set) var googleSync: GoogleSync?        // nil only in exotic test setups; set in init
var isGoogleConnected: Bool                     // googleAuth.isConnected
var googleStatus: String                        // transient text for the Settings section
func connectGoogle() async                      // loopback + browser + callback; updates googleStatus
func disconnectGoogle()
```

- [ ] **Step 1: Write the failing tests**

Create `TofuTests/GoogleWiringTests.swift`. Build `AppModel` the way `AppModelTests` does (temp-file `Store`, injected `SessionEngine` — copy the existing helper pattern from `AppModelTests.swift`, read that file first), then:

```swift
import XCTest
@testable import Tofu

@MainActor final class GoogleWiringTests: XCTestCase {
    // Use the same makeModel(...) helper style as AppModelTests, extended with:
    //   googleAPI: FakeGoogleAPI, googleAuth: GoogleAuth built over a TokenBox-style fake with token "rt-1"
    // AppModel's test initializer must accept `googleAPI: GoogleAPI?` and `googleAuth: GoogleAuth?`
    // (defaults nil → disconnected NullGoogleAPI behavior) — see Step 3.

    func testTogglingPriorityPushesPatch() async { /*
        model with connected fake; seed today's plan with a linked priority (googleTaskID "tA") via
        model.updatePlan(day: DayKey.key(for: Date())) { $0.priorities = [linked] };
        clear fake log; model.setPriority(linked.id, done: true, day: todayKey);
        poll the fake log (Task.yield loop, <=2 s) until it contains "patchTask tA - completed". */ }

    func testAddingPriorityInsertsTask() async { /*
        model.updatePlan(day: todayKey) { $0.priorities.append(Priority(title: "New")) };
        poll until log contains an entry starting "insertTask New". */ }

    func testMutatingAnotherDayPushesNothing() async { /*
        model.updatePlan(day: DayKey.next(todayKey)) { $0.priorities.append(Priority(title: "Tomorrow")) };
        wait ~200 ms; assert fake log has no insertTask. (Tomorrow's list is wrap-up territory, not the mirror.) */ }

    func testFinalizedSessionReachesCalendar() async { /*
        upsert a session with end + outcome .completed through model.upsertSession;
        poll until log contains an insertEvent entry. */ }

    func testHeartbeatUpsertDoesNotLogEvent() async { /*
        upsert a session with end == nil; wait ~200 ms; assert no insertEvent/insertCalendar in log. */ }

    func testDisconnectGoogleStopsSyncAndClearsToken() async { /*
        model.disconnectGoogle(); assert model.isGoogleConnected == false and the token box is nil. */ }
}
```

Write these out in full — the comments above are the behavior contract, not placeholders to leave in the file.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement in `AppModel.swift`**

1. **Stored properties** (after `mirror`):

```swift
    /// Google connection (OAuth) and the sync engine built over it. The engine is created at the end
    /// of init because its closures read the model.
    let googleAuth: GoogleAuth
    @ObservationIgnored private(set) var googleSync: GoogleSync?
    /// Transient text under the Connect button in Settings.
    var googleStatus = ""
```

2. **Designated init**: add parameters `googleAuth: GoogleAuth` and `googleAPI: GoogleAPI?` (the live convenience init passes a real `GoogleAuth()` and nil; the test convenience init takes `googleAuth: GoogleAuth? = nil, googleAPI: GoogleAPI? = nil` and passes a disconnected `GoogleAuth(readToken: { nil }, writeToken: { _ in })` when nil). At the END of the designated init (self fully initialized):

```swift
        let auth = googleAuth
        let api: GoogleAPI = googleAPI ?? GoogleClient(tokenProvider: { force in
            try await auth.accessToken(forceRefresh: force)
        })
        let sync = GoogleSync(api: api,
                              settings: { [weak self] in self?.data.settings ?? AppSettings() },
                              isConnected: { [weak self] in self?.googleAuth.isConnected ?? false },
                              plan: { [weak self] in
                                  let key = DayKey.key(for: Date())
                                  return self?.plan(for: key) ?? DayPlan(day: key)
                              },
                              applyPlan: { [weak self] plan in self?.applyGooglePlan(plan) },
                              saveCalendarID: { [weak self] id in
                                  self?.updateSettings { $0.googleCalendarID = id }
                              },
                              onError: { message in ToastCenter.shared.show(message) })
        googleSync = sync
        if auth.isConnected { sync.start() }
```

Ordering: `googleAuth` is assigned with the other stored properties (before any use of self); `googleSync` starts nil and is set by this block at the very end of init, once self is fully initialized and closures may capture it. `GoogleClient` is not `@MainActor`; its tokenProvider closure hops to the MainActor via `await`, which is fine.

3. **Write-through that does not echo** (`applyGooglePlan`): a plain plan write that does NOT call `googleSync.planChanged` (the sync already knows):

```swift
    /// GoogleSync writes a pulled plan through here; unlike `updatePlan` it never reports back to the sync.
    private func applyGooglePlan(_ plan: DayPlan) {
        if let index = data.dayPlans.firstIndex(where: { $0.day == plan.day }) {
            data.dayPlans[index] = plan
        } else {
            data.dayPlans.append(plan)
        }
        save()
    }
```

4. **Mutation routing in `updatePlan`** — capture before/after and report when it's today's actual day (the mirror targets `DayKey.key(now)`, not `DayPlanner.workingDay`, so a pending wrap-up never pollutes yesterday — spec §3):

```swift
    func updatePlan(day: String, _ mutate: (inout DayPlan) -> Void) {
        let before = plan(for: day) ?? DayPlan(day: day)
        if let index = data.dayPlans.firstIndex(where: { $0.day == day }) {
            mutate(&data.dayPlans[index])
        } else {
            var plan = DayPlan(day: day)
            mutate(&plan)
            data.dayPlans.append(plan)
        }
        save()
        if day == DayKey.key(for: Date()), let after = plan(for: day) {
            googleSync?.planChanged(from: before, to: after)
        }
    }
```

5. **Session routing in `upsertSession`** — after the existing save, finalized sessions only:

```swift
        if session.end != nil, session.outcome != nil {
            googleSync?.sessionEnded(session)
        }
```

6. **Connect / disconnect**:

```swift
    var isGoogleConnected: Bool { googleAuth.isConnected }

    /// Full connect flow: loopback listener, browser consent, code exchange, first sync (spec §1).
    func connectGoogle() async {
        let server = LoopbackServer()
        defer { server.stop() }
        googleStatus = "Waiting for Google…"
        do {
            let callback = AsyncThrowingStream<(String, String), Error> { continuation in
                do {
                    let port = try server.start { code, state in
                        guard let code, let state else { return }
                        continuation.yield((code, state))
                        continuation.finish()
                    }
                    let redirectURI = "http://127.0.0.1:\(port)"
                    let pending = googleAuth.beginAuth(redirectURI: redirectURI)
                    continuation.onTermination = { _ in }
                    NSWorkspace.shared.open(pending.url)
                    // Stash for the exchange below.
                    self.pendingRedirectURI = redirectURI
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 3 minute timeout so an abandoned consent tab doesn't hang the task forever.
            let result = try await withThrowingTaskGroup(of: (String, String)?.self) { group in
                group.addTask { for try await value in callback { return value }; return nil }
                group.addTask { try await Task.sleep(nanoseconds: 180_000_000_000); return nil }
                let first = try await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard let (code, state) = result else {
                googleStatus = "Timed out — try again."
                return
            }
            try await googleAuth.handleCallback(code: code, state: state, redirectURI: pendingRedirectURI)
            googleStatus = ""
            googleSync?.start()
        } catch {
            googleStatus = "Connection failed: \(error)"
        }
    }

    func disconnectGoogle() {
        googleSync?.stop()
        googleAuth.disconnect()
        googleStatus = ""
    }
```

Add `@ObservationIgnored private var pendingRedirectURI = ""` with the other properties. If the implementer finds a cleaner continuation shape (e.g. `withCheckedThrowingContinuation` guarded against double-resume), use it — the contract is: open browser, await one (code, state), 180 s timeout, exchange, start sync.

7. Check `convenience init` (test) signature change compiles every existing `AppModel(...)` call in `TofuTests` — the new parameters must all have defaults so existing tests build untouched.

- [ ] **Step 4: Run the new tests, then the FULL suite — PASS.** (The full suite matters: `updatePlan` is on many test paths.)

- [ ] **Step 5: Commit** — `feat: wire Google sync into AppModel`

---

### Task 10: UI — Settings section, Today/Morning event lists

**Files:**
- Modify: `Tofu/UI/SettingsView.swift`
- Modify: `Tofu/UI/TodayView.swift`
- Modify: `Tofu/UI/MorningScreen.swift`

**Interfaces:**
- Consumes: `AppModel.isGoogleConnected / connectGoogle / disconnectGoogle / googleStatus / googleSync?.todayEvents`, `AppSettings` toggles (Task 2), `GoogleEventFormat` (Task 8).
- Produces: user-visible UI only.

- [ ] **Step 1: SettingsView — add `googleSection` to the `Form` right after `discordSetupSection`**

Follow the section style already in the file (Section + header + caption footer, `Binding` helpers at the bottom):

```swift
    private var googleSection: some View {
        Section {
            if model.isGoogleConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                Toggle("Sync tasks with Google Tasks", isOn: googleTasksSyncEnabled)
                Toggle("Log sessions to Google Calendar", isOn: googleSessionLogEnabled)
                Toggle("Show today's events", isOn: googleShowEventsEnabled)
                Button("Disconnect") { model.disconnectGoogle() }
            } else {
                HStack(spacing: Theme.Space.s) {
                    Button("Connect Google…") { Task { await model.connectGoogle() } }
                    Text(model.googleStatus).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Google")
        } footer: {
            Text("Today's plan mirrors your default Google Tasks list, finished sessions are logged to a “Tofu” calendar, and today's events show on the morning screen. Sign-in shows “UIUC Collective Mind” — that's the shared app this uses. If Google disconnects you after a week, just connect again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
```

Plus the three `Binding<Bool>` helpers (copy the `companionEnabled` pattern): `googleTasksSyncEnabled`, `googleSessionLogEnabled`, `googleShowEventsEnabled`.

- [ ] **Step 2: TodayView — events list**

Read `TodayView.swift` fully first. Above the priorities list (inside the main VStack/List, before the priorities `ForEach` block), when the shown day is the current day:

```swift
        if model.data.settings.googleShowEventsEnabled, plan.day == DayKey.key(for: Date()),
           let events = model.googleSync?.todayEvents, !events.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Today's events").font(.headline)
                ForEach(events) { event in
                    HStack {
                        Text(GoogleEventFormat.timeLabel(event))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        Text(event.summary ?? "(untitled)")
                    }
                }
            }
        }
```

Adapt spacing/containers to whatever structure the file actually has (match siblings); the contract is: shown only on today, only when the toggle is on, only when non-empty; each row = time label + title; no interaction.

- [ ] **Step 3: MorningScreen — same list, compact**

Read `MorningScreen.swift` (`MorningView`); add the same block (shared row layout is fine to duplicate — two small view files beat a premature shared component) between the greeting and the priority cards, limited to the first 5 events (`events.prefix(5)`).

- [ ] **Step 4: Build + run the FULL test suite** (layout tests exist for these screens — e.g. `MorningTests`; fix anything the new block breaks).

Run: full suite command.
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit** — `feat: Google settings section and today's events in Today and Morning`

---

### Task 11: Final verification

**Files:** none new.

- [ ] **Step 1: Full suite, clean**

Run: `cd /Users/axion66/coding/accountabilibrosis/Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' -derivedDataPath build/DerivedData test 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: TEST SUCCEEDED, zero failures.

- [ ] **Step 2: Spec sweep**

Re-read `docs/superpowers/specs/2026-10-15-google-sync-design.md` top to bottom; confirm each numbered section has shipped behavior (§1 auth, §2 client, §3 mirror, §4 calendar, §5 settings/wiring, §6 errors, §7 tests). Fix gaps before declaring done.

- [ ] **Step 3: Release build compiles**

Run: `xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit any fixes** — `fix: <what>` per issue found.
