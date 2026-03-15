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
        case .finish:
            isFinished = true
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
        case .data(let name, let payload):
            message.parts.append(.data(DataPart(name: name, data: payload)))
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

    /// Convenience: apply an array of chunks in order.
    public mutating func applyAll(_ chunks: [UIMessageChunk]) {
        for chunk in chunks {
            apply(chunk)
        }
    }
}
