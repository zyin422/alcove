import Foundation
import Network

/// One-shot localhost HTTP listener for the OAuth redirect (http://127.0.0.1:<port>).
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tofu.google.loopback")

    /// Starts listening on an ephemeral port; returns it. `onCallback` fires on the main queue once.
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
        self.listener = nil
        throw GoogleError.transport("loopback listener got no port")
    }

    /// Stops listening.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// code/state from "GET /?code=...&state=... HTTP/1.1"; pure, for tests.
    static func parse(requestLine: String) -> (code: String?, state: String?) {
        guard let pathPart = requestLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathPart)) else { return (nil, nil) }
        let items = components.queryItems ?? []
        return (items.first { $0.name == "code" }?.value, items.first { $0.name == "state" }?.value)
    }
}
