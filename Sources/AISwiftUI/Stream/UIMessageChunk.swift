/// A single decoded chunk from the AI SDK UI message stream protocol.
/// Each chunk is decoded from a `data: {...}` SSE line.
public enum UIMessageChunk: Sendable {
    // MARK: - Lifecycle
    /// Stream opened; carries the message ID assigned by the server.
    case start(messageId: String, metadata: [String: JSONValue]? = nil)
    /// A new model step has started (may contain multiple tool calls or text).
    case startStep
    /// Current step finished.
    case finishStep
    /// Stream finished successfully; `finishReason` from the server (e.g. "stop", "length").
    case finish(finishReason: String? = nil, metadata: [String: JSONValue]? = nil)
    /// Stream terminated with an error.
    case error(text: String)

    // MARK: - Text
    /// A text block has started; `id` identifies the block within the message.
    case textStart(id: String)
    /// An incremental text delta.
    case textDelta(id: String, delta: String)
    /// The text block has ended.
    case textEnd(id: String)

    // MARK: - Reasoning
    /// A reasoning block has started.
    case reasoningStart(id: String)
    /// An incremental reasoning delta.
    case reasoningDelta(id: String, delta: String)
    /// The reasoning block has ended; `signature` is present when redacted.
    case reasoningEnd(id: String, signature: String?)

    // MARK: - Tool
    /// Tool input streaming has started.
    case toolInputStart(toolCallId: String, toolName: String)
    /// Incremental tool input JSON delta.
    case toolInputDelta(toolCallId: String, inputTextDelta: String)
    /// Tool input is fully available.
    case toolInputAvailable(toolCallId: String, toolName: String, input: JSONValue)
    /// Tool output is available.
    case toolOutputAvailable(toolCallId: String, output: JSONValue)

    // MARK: - Sources
    /// A single source URL reference.
    case source(id: String?, url: String, title: String?)
    /// Multiple source URL references at once.
    case sources([SourceURLPart])

    // MARK: - Custom data
    /// A custom `data-{name}` chunk carrying an arbitrary JSON payload.
    case data(name: String, payload: JSONValue, isTransient: Bool = false, dataId: String? = nil)

    // MARK: - New chunk types (ai-3on.7)

    /// Message-level metadata from a `message-metadata` chunk.
    case messageMetadata(metadata: [String: JSONValue])

    /// Stream aborted; optional human-readable reason.
    case abort(reason: String?)

    /// A structured source URL reference from a `source-url` chunk.
    case sourceURL(sourceId: String, url: String, title: String?)

    /// A structured source document reference from a `source-document` chunk.
    case sourceDocument(sourceId: String, mediaType: String, title: String, filename: String)

    /// A file attachment from a `file` chunk.
    case file(url: String, mediaType: String)
}
