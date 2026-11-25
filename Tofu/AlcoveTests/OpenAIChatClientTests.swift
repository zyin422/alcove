import XCTest
@testable import Alcove

private struct FailingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

/// A chat-completions body with plain text.
func chatTextBody(_ text: String) -> Data {
    let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
    return MockTransport.json(#"""
    {"id": "chatcmpl-1", "object": "chat.completion",
     "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": \#(escaped)}}]}
    """#)
}

/// A chat-completions body whose message carries tool calls (content null) — `arguments` is a JSON object string.
func chatToolBody(_ calls: [(id: String, name: String, arguments: String)], content: String? = nil) -> Data {
    let encodedCalls = calls.map { call -> String in
        let args = String(data: try! JSONEncoder().encode(call.arguments), encoding: .utf8)!
        return #"{"id": "\#(call.id)", "type": "function", "function": {"name": "\#(call.name)", "arguments": \#(args)}}"#
    }.joined(separator: ",")
    let contentJSON = content.map { String(data: try! JSONEncoder().encode($0), encoding: .utf8)! } ?? "null"
    return MockTransport.json(#"""
    {"id": "chatcmpl-2", "object": "chat.completion",
     "choices": [{"index": 0, "finish_reason": "tool_calls",
                  "message": {"role": "assistant", "content": \#(contentJSON), "tool_calls": [\#(encodedCalls)]}}]}
    """#)
}

final class OpenAIChatClientTests: XCTestCase {
    private func makeClient(_ transport: HTTPTransport, timeout: TimeInterval = 20) -> OpenAIChatClient {
        OpenAIChatClient(apiKey: "sk-test", transport: transport, timeout: timeout)
    }

    private let tools = [
        ChatToolDefinition(name: "allow_site", description: "Allow",
                           properties: ["host": .init(description: "host"), "reason": .init(description: "why")],
                           required: ["host", "reason"]),
    ]

    private func body(of request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Request

    func testRequestMethodURLHeadersAndTimeout() async throws {
        let transport = MockTransport { _ in (200, chatTextBody("hi")) }
        _ = try await makeClient(transport).complete(messages: [.user("hello")], tools: tools)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 20)
    }

    func testRequestBodyCarriesModelSamplingMessagesAndTools() async throws {
        let transport = MockTransport { _ in (200, chatTextBody("hi")) }
        _ = try await makeClient(transport).complete(messages: [.system("be nice"), .user("hello")], tools: tools)

        let json = try body(of: transport.requests.first)
        XCTAssertEqual(json["model"] as? String, "gpt-4.1-mini")
        XCTAssertEqual(json["temperature"] as? Double, 0.3)
        XCTAssertEqual(json["max_tokens"] as? Int, 300)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(messages.map { $0["content"] as? String }, ["be nice", "hello"])

        let wireTools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(wireTools.count, 1)
        XCTAssertEqual(wireTools[0]["type"] as? String, "function")
        let function = try XCTUnwrap(wireTools[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "allow_site")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual((parameters["required"] as? [String])?.sorted(), ["host", "reason"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: [String: Any]])
        XCTAssertEqual(properties["host"]?["type"] as? String, "string")
    }

    func testEmptyToolsAreOmitted() async throws {
        let transport = MockTransport { _ in (200, chatTextBody("hi")) }
        _ = try await makeClient(transport).complete(messages: [.user("hello")], tools: [])
        XCTAssertNil(try body(of: transport.requests.first)["tools"])
    }

    func testAssistantToolCallAndToolResultMessagesEncodeOnTheWire() async throws {
        let call = ChatToolCall(id: "call_1", name: "close_site", arguments: #"{"host":"reddit.com","reason":"fun"}"#)
        let transport = MockTransport { _ in (200, chatTextBody("done")) }
        _ = try await makeClient(transport).complete(
            messages: [.user("x"), .assistant(nil, toolCalls: [call]), .tool(callID: "call_1", content: "ok")],
            tools: tools)

        let messages = try XCTUnwrap(try body(of: transport.requests.first)["messages"] as? [[String: Any]])
        let assistant = messages[1]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let wireCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(wireCalls[0]["id"] as? String, "call_1")
        XCTAssertEqual(wireCalls[0]["type"] as? String, "function")
        let function = try XCTUnwrap(wireCalls[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "close_site")
        XCTAssertEqual(function["arguments"] as? String, #"{"host":"reddit.com","reason":"fun"}"#)
        let tool = messages[2]
        XCTAssertEqual(tool["role"] as? String, "tool")
        XCTAssertEqual(tool["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(tool["content"] as? String, "ok")
    }

    // MARK: - Response

    func testParsesTextContent() async throws {
        let transport = MockTransport { _ in (200, chatTextBody("Hey there")) }
        let completion = try await makeClient(transport).complete(messages: [.user("hi")], tools: tools)
        XCTAssertEqual(completion.content, "Hey there")
        XCTAssertEqual(completion.toolCalls, [])
    }

    func testParsesToolCallsWithNullContent() async throws {
        let transport = MockTransport { _ in
            (200, chatToolBody([("call_a", "allow_site", #"{"host":"youtube.com","reason":"lecture"}"#),
                                ("call_b", "close_site", #"{"host":"reddit.com","reason":"fun"}"#)]))
        }
        let completion = try await makeClient(transport).complete(messages: [.user("hi")], tools: tools)
        XCTAssertNil(completion.content)
        XCTAssertEqual(completion.toolCalls.map(\.id), ["call_a", "call_b"])
        XCTAssertEqual(completion.toolCalls.map(\.function.name), ["allow_site", "close_site"])
        XCTAssertEqual(completion.toolCalls[0].function.arguments, #"{"host":"youtube.com","reason":"lecture"}"#)
    }

    // MARK: - Errors

    func testNon2xxThrowsHTTP() async {
        let transport = MockTransport { _ in (500, MockTransport.json("{}")) }
        do {
            _ = try await makeClient(transport).complete(messages: [.user("hi")], tools: tools)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ChatClientError, .http(500))
        }
    }

    func testBodyWithoutChoicesThrowsDecoding() async {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"choices": []}"#)) }
        do {
            _ = try await makeClient(transport).complete(messages: [.user("hi")], tools: tools)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ChatClientError, .decoding)
        }
    }

    func testGarbageBodyThrowsDecoding() async {
        let transport = MockTransport { _ in (200, MockTransport.json("not json")) }
        do {
            _ = try await makeClient(transport).complete(messages: [.user("hi")], tools: tools)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ChatClientError, .decoding)
        }
    }

    func testTransportFailureThrowsTransport() async {
        do {
            _ = try await makeClient(FailingTransport()).complete(messages: [.user("hi")], tools: tools)
            XCTFail("expected throw")
        } catch {
            guard case .transport(let reason)? = error as? ChatClientError else {
                return XCTFail("expected .transport, got \(error)")
            }
            XCTAssertFalse(reason.isEmpty)
        }
    }
}
