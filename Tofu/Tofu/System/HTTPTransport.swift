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
