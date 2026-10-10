// AccountabilibrosisTests/MockTransport.swift — REAL CODE (created in Task 6, reused by Task 12)
import Foundation
@testable import Accountabilibrosis

/// Scripted HTTPTransport. `handler` maps each request to (statusCode, body). Records every request.
final class MockTransport: HTTPTransport {
    var handler: (URLRequest) -> (Int, Data)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        return (body, response)
    }

    /// "METHOD /path" for each recorded request, e.g. "POST /api/v10/channels/1/messages".
    var log: [String] { requests.map { "\($0.httpMethod ?? "GET") \($0.url?.path ?? "")" } }

    static func json(_ string: String) -> Data { Data(string.utf8) }
}
