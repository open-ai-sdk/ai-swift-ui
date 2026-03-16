/// Applies a sequence of `UIMessageChunk` values to produce an incrementally-updated
/// assistant `UIMessage`.
///
/// The reducer is a value type; callers maintain state across calls.
/// Typical usage: create one reducer per assistant message, feed all chunks in order.
public struct UIMessageStreamReducer: Sendable {

    /// The message being constructed. Callers read this after each `apply` call.
    public private(set) var message: UIMessage

    /// Set when a terminal `error` chunk is received.
    public private(set) var error: String?

    /// Set to `true` when a `finish` chunk is received.
    public private(set) var isFinished: Bool = false

    /// The finish reason from the `finish` chunk (e.g. "stop", "length").
    public private(set) var finishReason: String?

    /// Set to `true` when an `abort` chunk is received.
    public private(set) var isAborted: Bool = false

    // MARK: - Private mutable state

    // Tracks open text/reasoning block indices by their id
    private var textBlockIndices: [String: Int] = [:]
    private var reasoningBlockIndices: [String: Int] = [:]

    // Tracks tool invocation part indices by toolCallId
    private var toolPartIndices: [String: Int] = [:]

    public init(messageId: String) {
        self.message = UIMessage(id: messageId, role: .assistant, parts: [])
    }

    /// Apply a single chunk, mutating the reducer's `message` state.
    public mutating func apply(_ chunk: UIMessageChunk) {
        switch chunk {
        case .start(let msgId):
            resetState(messageId: msgId)
        case .startStep, .finishStep, .textEnd, .toolInputDelta:
            break
        case .finish(let reason):
            isFinished = true
            finishReason = reason
        case .error(let text):
            error = text
        case .textStart, .textDelta:
            applyTextChunk(chunk)
        case .reasoningStart, .reasoningDelta, .reasoningEnd:
            applyReasoningChunk(chunk)
        case .toolInputStart, .toolInputAvailable, .toolOutputAvailable:
            applyToolChunk(chunk)
        case .source(let id, let url, let title):
            message.parts.append(.sourceURL(SourceURLPart(id: id, url: url, title: title)))
        case .sources(let list):
            for src in list { message.parts.append(.sourceURL(src)) }
        case .data(let name, let payload, let isTransient, let dataId):
            applyDataChunk(name: name, payload: payload, isTransient: isTransient, dataId: dataId)
        case .messageMetadata(let metadata):
            message.metadata = metadata
        case .abort(let reason):
            isAborted = true
            error = reason ?? "aborted"
        case .sourceURL(let sourceId, let url, let title):
            message.parts.append(.sourceURL(SourceURLPart(id: sourceId, url: url, title: title)))
        case .sourceDocument(let sourceId, let mediaType, let title, let filename):
            message.parts.append(.sourceDocument(SourceDocumentPart(
                id: sourceId, title: title, mediaType: mediaType, url: nil, content: nil, filename: filename
            )))
        case .file(let url, let mediaType):
            message.parts.append(.file(FilePart(url: url, mediaType: mediaType)))
        }
    }

    // MARK: - Private chunk handlers

    private mutating func resetState(messageId: String) {
        message = UIMessage(id: messageId, role: .assistant, parts: [])
        textBlockIndices = [:]
        reasoningBlockIndices = [:]
        toolPartIndices = [:]
    }

    private mutating func applyTextChunk(_ chunk: UIMessageChunk) {
        switch chunk {
        case .textStart(let id):
            textBlockIndices[id] = message.parts.count
            message.parts.append(.text(TextPart(text: "")))
        case .textDelta(let id, let delta):
            guard let idx = textBlockIndices[id],
                  case .text(var p) = message.parts[idx] else { return }
            p.text += delta
            message.parts[idx] = .text(p)
        default: break
        }
    }

    private mutating func applyReasoningChunk(_ chunk: UIMessageChunk) {
        switch chunk {
        case .reasoningStart(let id):
            reasoningBlockIndices[id] = message.parts.count
            message.parts.append(.reasoning(ReasoningPart(reasoning: "")))
        case .reasoningDelta(let id, let delta):
            guard let idx = reasoningBlockIndices[id],
                  case .reasoning(var p) = message.parts[idx] else { return }
            p.reasoning += delta
            message.parts[idx] = .reasoning(p)
        case .reasoningEnd(let id, let signature):
            guard let idx = reasoningBlockIndices[id],
                  case .reasoning(var p) = message.parts[idx] else { return }
            p.signature = signature
            message.parts[idx] = .reasoning(p)
        default: break
        }
    }

    private mutating func applyToolChunk(_ chunk: UIMessageChunk) {
        switch chunk {
        case .toolInputStart(let tcId, let toolName):
            toolPartIndices[tcId] = message.parts.count
            message.parts.append(.toolInvocation(ToolInvocationPart(
                toolCallId: tcId, toolName: toolName, state: .inputStreaming, input: .null
            )))
        case .toolInputAvailable(let tcId, let toolName, let input):
            if let idx = toolPartIndices[tcId],
               case .toolInvocation(var p) = message.parts[idx] {
                p.state = .inputAvailable
                p.input = input
                p.toolName = toolName
                message.parts[idx] = .toolInvocation(p)
            } else {
                toolPartIndices[tcId] = message.parts.count
                message.parts.append(.toolInvocation(ToolInvocationPart(
                    toolCallId: tcId, toolName: toolName, state: .inputAvailable, input: input
                )))
            }
        case .toolOutputAvailable(let tcId, let output):
            guard let idx = toolPartIndices[tcId],
                  case .toolInvocation(var p) = message.parts[idx] else { return }
            p.state = .outputAvailable
            p.output = output
            message.parts[idx] = .toolInvocation(p)
        default: break
        }
    }

    /// Handles `data-*` chunks. `data-document-references` is promoted to
    /// `.sourceDocument` parts; all others land as generic `DataPart`.
    private mutating func applyDataChunk(name: String, payload: JSONValue, isTransient: Bool = false, dataId: String? = nil) {
        if name == "document-references", case .array(let items) = payload {
            for item in items {
                guard case .object(let obj) = item else { continue }
                let id = obj["id"]?.stringValue
                let title = obj["title"]?.stringValue
                message.parts.append(.sourceDocument(SourceDocumentPart(id: id, title: title)))
            }
        } else {
            message.parts.append(.data(DataPart(name: name, data: payload, isTransient: isTransient, id: dataId)))
        }
    }

    /// Convenience: apply an array of chunks in order.
    public mutating func applyAll(_ chunks: [UIMessageChunk]) {
        for chunk in chunks {
            apply(chunk)
        }
    }
}
