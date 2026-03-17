import Foundation

/// Options that the caller attaches to a chat request.
public struct ChatRequestOptions: Sendable {
    /// Additional key/value pairs merged into the request body (route/model hints).
    /// Examples: modelId, agentId, runId, attachments.
    public var body: [String: JSONValue]

    /// App-level observability metadata NOT forwarded to the model.
    /// Examples: threadId, userId, experimentId.
    public var metadata: [String: JSONValue]

    /// Extra HTTP headers added to this specific request.
    public var headers: [String: String]

    public init(
        body: [String: JSONValue] = [:],
        metadata: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.body = body
        self.metadata = metadata
        self.headers = headers
    }
}

/// The request payload passed from `ChatSession` to a `ChatTransport`.
public struct TransportSendRequest: Sendable {
    /// The session or conversation identifier.
    public let id: String
    /// Full conversation history to send to the model.
    public let messages: [UIMessage]
    /// Optional per-request options.
    public let options: ChatRequestOptions?

    public init(id: String, messages: [UIMessage], options: ChatRequestOptions? = nil) {
        self.id = id
        self.messages = messages
        self.options = options
    }
}

// MARK: - Codable envelope types for HTTPChatTransport default body encoding

/// Wire-format envelope sent to the server.
struct ChatRequestEnvelope: Encodable {
    let id: String
    let messages: [EncodableMessage]
    let body: [String: JSONValue]?
    let metadata: [String: JSONValue]?
}

struct EncodableMessage: Encodable {
    let role: String
    /// Fallback when no encodable parts exist.
    let content: String?
    let parts: [EncodableMessagePart]?
}

enum EncodableMessagePart: Encodable {
    case text(String)
    case file(EncodableFilePart, type: String)  // type = "file" | "image"

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .file(let fp, let partType):
            try container.encode(partType, forKey: .type)
            try container.encode(fp.mediaType, forKey: .mediaType)
            if let name = fp.name { try container.encode(name, forKey: .name) }
            if let fileId = fp.fileId, !fileId.isEmpty {
                try container.encode(fileId, forKey: .fileId)
            } else if let data = fp.data, !data.isEmpty {
                try container.encode(data.base64EncodedString(), forKey: .data)
            } else if !fp.url.isEmpty {
                try container.encode(fp.url, forKey: .url)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, mediaType, name, fileId, data, url
    }
}

struct EncodableFilePart {
    let mediaType: String
    let name: String?
    let url: String
    let data: Data?
    let fileId: String?
}

/// Mutable options passed to the `prepareSendRequest` hook.
public struct PreparedSendRequest: Sendable {
    public var api: URL
    public var chatId: String
    public var messages: [UIMessage]
    public var body: [String: JSONValue]
    public var headers: [String: String]

    public init(
        api: URL,
        chatId: String,
        messages: [UIMessage],
        body: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.api = api
        self.chatId = chatId
        self.messages = messages
        self.body = body
        self.headers = headers
    }
}
