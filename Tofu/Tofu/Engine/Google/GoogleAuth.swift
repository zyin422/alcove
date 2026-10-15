import CryptoKit
import Foundation
import Security

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
