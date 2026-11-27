import XCTest
@testable import Alcove

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
