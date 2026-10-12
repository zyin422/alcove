import Foundation

/// Subset of a partial guild from `GET /users/@me/guilds`.
struct DiscordGuild: Decodable, Equatable {
    let id: String
    let name: String
}

/// Subset of the bot user from `GET /users/@me`.
struct DiscordUser: Decodable, Equatable {
    let id: String
    let username: String
}

enum DiscordError: Error, Equatable {
    /// Non-2xx status after at most one 429 retry.
    case http(Int)
    /// The request never produced an HTTP response (offline, DNS, TLS...).
    case transport(String)
    /// A 2xx body that did not decode, or a body that could not be encoded.
    case decoding
}

/// Seam between `DiscordClient` and the network so tests can script responses.
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

/// Outcome of `DiscordClient.broadcast`.
struct DiscordPostReport: Equatable {
    var posted: [String: String] = [:]   // guildID -> channelID
    var failedGuilds: [String] = []
}

/// Minimal Discord REST client for a bot token (spec §9).
final class DiscordClient {
    static let baseURL = URL(string: "https://discord.com/api/v10")!
    static let userAgent = "DiscordBot (tofu, 1.0)"
    /// Channels tried per guild before giving up on it.
    static let maxCandidatesPerGuild = 5
    /// Longest 429 wait we honor; a longer `retry_after` is clamped so a session end never hangs for minutes.
    static let maxRetryAfter: TimeInterval = 30

    private let token: String
    private let transport: HTTPTransport
    private let sleep: (TimeInterval) async -> Void

    init(token: String, transport: HTTPTransport = URLSessionTransport(),
         sleep: @escaping (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
         }) {
        self.token = token
        self.transport = transport
        self.sleep = sleep
    }

    func me() async throws -> DiscordUser {
        try await get(["users", "@me"])
    }

    func guilds() async throws -> [DiscordGuild] {
        try await get(["users", "@me", "guilds"])
    }

    func channels(guildID: String) async throws -> [DiscordChannel] {
        try await get(["guilds", guildID, "channels"])
    }

    /// 429 -> sleep(retry_after) once and retry; other non-2xx -> DiscordError.http(code).
    func post(channelID: String, content: String) async throws {
        let message = OutgoingMessage(content: content, allowedMentions: .init(parse: []))
        let body: Data
        do {
            body = try JSONEncoder().encode(message)
        } catch {
            throw DiscordError.decoding
        }
        _ = try await send(method: "POST", path: ["channels", channelID, "messages"], body: body)
    }

    /// Every guild: try ChannelPicker candidates (max 5) until one succeeds. Never throws.
    func broadcast(_ content: String, channelCache: [String: String]) async -> DiscordPostReport {
        var report = DiscordPostReport()
        let allGuilds: [DiscordGuild]
        do {
            allGuilds = try await guilds()
        } catch {
            return report
        }
        for guild in allGuilds {
            if let channelID = await postToGuild(guild.id, content: content, cachedID: channelCache[guild.id]) {
                report.posted[guild.id] = channelID
            } else {
                report.failedGuilds.append(guild.id)
            }
        }
        return report
    }

    // MARK: - Private

    /// Returns the channel that accepted the message, or nil when every candidate failed.
    private func postToGuild(_ guildID: String, content: String, cachedID: String?) async -> String? {
        let guildChannels: [DiscordChannel]
        do {
            guildChannels = try await channels(guildID: guildID)
        } catch {
            return nil
        }
        let candidates = ChannelPicker.candidates(from: guildChannels, cachedID: cachedID)
        for channelID in candidates.prefix(Self.maxCandidatesPerGuild) {
            do {
                try await post(channelID: channelID, content: content)
                return channelID
            } catch {
                continue
            }
        }
        return nil
    }

    private func get<T: Decodable>(_ path: [String]) async throws -> T {
        let data = try await send(method: "GET", path: path, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DiscordError.decoding
        }
    }

    /// Sends once; on 429 sleeps `retry_after` and sends exactly one more time. Returns the 2xx body.
    private func send(method: String, path: [String], body: Data?) async throws -> Data {
        let request = makeRequest(method: method, path: path, body: body)
        var (data, response) = try await perform(request)
        if response.statusCode == 429 {
            await sleep(Self.retryAfter(body: data, response: response))
            (data, response) = try await perform(request)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw DiscordError.http(response.statusCode)
        }
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as DiscordError {
            throw error
        } catch {
            throw DiscordError.transport(error.localizedDescription)
        }
    }

    /// Each path element is one URL component (a "/" inside an id is percent-encoded, never a new segment).
    private func makeRequest(method: String, path: [String], body: Data?) -> URLRequest {
        var url = Self.baseURL
        for component in path {
            url.append(component: component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    /// `retry_after` (seconds, JSON body), else the Retry-After header, else 1 s; clamped to 0...maxRetryAfter.
    private static func retryAfter(body: Data, response: HTTPURLResponse) -> TimeInterval {
        let seconds: TimeInterval
        if let limit = try? JSONDecoder().decode(RateLimitBody.self, from: body) {
            seconds = limit.retryAfter
        } else if let header = response.value(forHTTPHeaderField: "Retry-After"), let value = TimeInterval(header) {
            seconds = value
        } else {
            seconds = 1
        }
        guard seconds.isFinite else { return maxRetryAfter }
        return min(max(0, seconds), maxRetryAfter)
    }
}

/// Body of `POST /channels/{id}/messages`. Empty `parse` disables every @mention ping.
private struct OutgoingMessage: Encodable {
    struct AllowedMentions: Encodable {
        let parse: [String]
    }

    let content: String
    let allowedMentions: AllowedMentions

    enum CodingKeys: String, CodingKey {
        case content
        case allowedMentions = "allowed_mentions"
    }
}

/// Body of a 429 response.
private struct RateLimitBody: Decodable {
    let retryAfter: TimeInterval

    enum CodingKeys: String, CodingKey {
        case retryAfter = "retry_after"
    }
}
