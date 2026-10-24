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
/// A user message with `images` is sent in the vision form: `content` becomes an array of a text part and one
/// `image_url` part per image (data URLs, low detail). Images are never decoded back.
struct ChatWireMessage: Codable, Equatable {
    var role: String
    var content: String?
    var toolCalls: [ChatToolCall]?
    var toolCallID: String?
    var images: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(role: String, content: String?, toolCalls: [ChatToolCall]? = nil, toolCallID: String? = nil,
         images: [String]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.images = images
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let images, !images.isEmpty {
            var parts = container.nestedUnkeyedContainer(forKey: .content)
            try parts.encode(ContentPart.text(content ?? ""))
            for url in images { try parts.encode(ContentPart.image(url)) }
        } else {
            try container.encodeIfPresent(content, forKey: .content)
        }
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }

    /// One element of a vision message's `content` array.
    private enum ContentPart: Encodable {
        case text(String)
        case image(String)

        private enum Keys: String, CodingKey { case type, text, imageURL = "image_url" }
        private enum ImageKeys: String, CodingKey { case url, detail }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let url):
                try container.encode("image_url", forKey: .type)
                var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                try image.encode(url, forKey: .url)
                try image.encode("low", forKey: .detail)
            }
        }
    }

    /// A user message carrying JPEG screenshots alongside its text.
    static func user(_ text: String, jpegs: [Data]) -> ChatWireMessage {
        ChatWireMessage(role: "user", content: text,
                        images: jpegs.map { "data:image/jpeg;base64," + $0.base64EncodedString() })
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
    /// `"json_object"` when the reply must be one JSON object. Omitted otherwise, so it is not sent as null.
    var responseFormat: ResponseFormat?

    struct ResponseFormat: Encodable, Equatable {
        var type = "json_object"
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(responseFormat, forKey: .responseFormat)
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
    /// `json` asks for a single JSON object (`response_format`). The prompt must mention JSON.
    func complete(messages: [ChatWireMessage], tools: [ChatToolDefinition], maxTokens: Int? = nil,
                  json: Bool = false) async throws -> ChatCompletion {
        let body: Data
        do {
            body = try JSONEncoder().encode(ChatCompletionRequest(
                model: Self.model, messages: messages, tools: tools.isEmpty ? nil : tools,
                temperature: Self.temperature, maxTokens: maxTokens ?? Self.maxTokens,
                responseFormat: json ? .init() : nil))
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

    /// The span of a model reply from its first "{" to its last "}", as UTF-8, so prose or a code fence around
    /// the JSON object is ignored. nil when there is no such span.
    static func jsonObject(in reply: String) -> Data? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else { return nil }
        return Data(reply[start...end].utf8)
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
