import Foundation

enum ChatClientError: Error, Equatable {
    /// Non-2xx status.
    case http(Int)
    /// A 2xx body without a usable `choices[0].message`, or a request that could not be encoded.
    case decoding
    /// The request never produced an HTTP response (offline, DNS, TLS, timeout...).
    case transport(String)
}

/// One function call requested by the model (also echoed back inside the assistant message that made it).
struct ChatToolCall: Codable, Equatable {
    struct Function: Codable, Equatable {
        var name: String
        /// JSON object, as a string (that is how the API sends it).
        var arguments: String
    }
    var id: String
    var type = "function"
    var function: Function

    init(id: String, name: String, arguments: String) {
        self.id = id
        self.function = Function(name: name, arguments: arguments)
    }
}

/// One message on the wire (`system`, `user`, `assistant`, or `tool`).
struct ChatWireMessage: Codable, Equatable {
    var role: String
    var content: String?
    var toolCalls: [ChatToolCall]?
    var toolCallID: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    static func system(_ text: String) -> ChatWireMessage { ChatWireMessage(role: "system", content: text) }
    static func user(_ text: String) -> ChatWireMessage { ChatWireMessage(role: "user", content: text) }
    static func assistant(_ text: String?, toolCalls: [ChatToolCall]? = nil) -> ChatWireMessage {
        ChatWireMessage(role: "assistant", content: text, toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls)
    }
    static func tool(callID: String, content: String) -> ChatWireMessage {
        ChatWireMessage(role: "tool", content: content, toolCallID: callID)
    }
}

/// A function the model may call, with its JSON-schema parameters.
struct ChatToolDefinition: Encodable, Equatable {
    struct Property: Encodable, Equatable {
        var type = "string"
        var description: String
    }
    struct Parameters: Encodable, Equatable {
        var type = "object"
        var properties: [String: Property]
        var required: [String]
    }
    struct Function: Encodable, Equatable {
        var name: String
        var description: String
        var parameters: Parameters
    }
    var type = "function"
    var function: Function

    init(name: String, description: String, properties: [String: Property], required: [String]) {
        function = Function(name: name, description: description,
                            parameters: Parameters(properties: properties, required: required))
    }
}

/// What the model said: text, tool calls, or both.
struct ChatCompletion: Equatable {
    var content: String?
    var toolCalls: [ChatToolCall]
}

/// Body of `POST /v1/chat/completions`.
struct ChatCompletionRequest: Encodable, Equatable {
    var model: String
    var messages: [ChatWireMessage]
    /// Omitted when empty (the final round of a tool loop is sent without tools).
    var tools: [ChatToolDefinition]?
    var temperature: Double
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature
        case maxTokens = "max_tokens"
    }
}

/// Minimal client for the OpenAI Chat Completions API (gpt-4.1-mini with tool calling).
final class OpenAIChatClient {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let model = "gpt-4.1-mini"
    static let temperature = 0.3
    static let maxTokens = 300

    private let apiKey: String
    private let transport: HTTPTransport
    private let timeout: TimeInterval

    init(apiKey: String, transport: HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 20) {
        self.apiKey = apiKey
        self.transport = transport
        self.timeout = timeout
    }

    /// One round trip. Throws `ChatClientError` (http, decoding, transport).
    func complete(messages: [ChatWireMessage], tools: [ChatToolDefinition]) async throws -> ChatCompletion {
        let body: Data
        do {
            body = try JSONEncoder().encode(ChatCompletionRequest(
                model: Self.model, messages: messages, tools: tools.isEmpty ? nil : tools,
                temperature: Self.temperature, maxTokens: Self.maxTokens))
        } catch {
            throw ChatClientError.decoding
        }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as ChatClientError {
            throw error
        } catch {
            throw ChatClientError.transport(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ChatClientError.http(response.statusCode)
        }
        return try Self.parse(data)
    }

    // MARK: - Private

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
                var toolCalls: [ChatToolCall]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            var message: Message
        }
        var choices: [Choice]
    }

    /// `choices[0].message` -> text + tool calls.
    private static func parse(_ data: Data) throws -> ChatCompletion {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let message = response.choices.first?.message else {
            throw ChatClientError.decoding
        }
        return ChatCompletion(content: message.content, toolCalls: message.toolCalls ?? [])
    }
}
