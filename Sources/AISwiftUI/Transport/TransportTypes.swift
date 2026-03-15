import Foundation

/// Options that the caller attaches to a chat request.
public struct ChatRequestOptions: Sendable {
    /// Additional key/value pairs merged into the request body (route/model hints).
    /// Examples: modelId, agentId, runId, attachments.
    public var body: [String: any Sendable]

    /// App-level observability metadata NOT forwarded to the model.
    /// Examples: threadId, userId, experimentId.
    public var metadata: [String: any Sendable]

    /// Extra HTTP headers added to this specific request.
    public var headers: [String: String]

    public init(
        body: [String: any Sendable] = [:],
        metadata: [String: any Sendable] = [:],
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
