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
            message = UIMessage(id: msgId, role: .assistant, parts: [])
            textBlockIndices = [:]
            reasoningBlockIndices = [:]
            toolPartIndices = [:]

        case .startStep, .finishStep:
            break  // no direct part mutation needed

        case .finish:
            isFinished = true

        case .error(let text):
            error = text

        case .textStart(let id):
            let idx = message.parts.count
            textBlockIndices[id] = idx
            message.parts.append(.text(TextPart(text: "")))

        case .textDelta(let id, let delta):
            guard let idx = textBlockIndices[id] else { return }
            if case .text(var p) = message.parts[idx] {
                p.text += delta
                message.parts[idx] = .text(p)
            }

        case .textEnd:
            break  // block stays in parts list

        case .reasoningStart(let id):
            let idx = message.parts.count
            reasoningBlockIndices[id] = idx
            message.parts.append(.reasoning(ReasoningPart(reasoning: "")))

        case .reasoningDelta(let id, let delta):
            guard let idx = reasoningBlockIndices[id] else { return }
            if case .reasoning(var p) = message.parts[idx] {
                p.reasoning += delta
                message.parts[idx] = .reasoning(p)
            }

        case .reasoningEnd(let id, let signature):
            guard let idx = reasoningBlockIndices[id] else { return }
            if case .reasoning(var p) = message.parts[idx] {
                p.signature = signature
                message.parts[idx] = .reasoning(p)
            }

        case .toolInputStart(let tcId, let toolName):
            let idx = message.parts.count
            toolPartIndices[tcId] = idx
            let part = ToolInvocationPart(
                toolCallId: tcId,
                toolName: toolName,
                state: .inputStreaming,
                input: .null
            )
            message.parts.append(.toolInvocation(part))

        case .toolInputDelta:
            // Delta is informational; input is finalized in toolInputAvailable
            break

        case .toolInputAvailable(let tcId, let toolName, let input):
            if let idx = toolPartIndices[tcId],
               case .toolInvocation(var p) = message.parts[idx] {
                p.state = .inputAvailable
                p.input = input
                p.toolName = toolName
                message.parts[idx] = .toolInvocation(p)
            } else {
                // First appearance without prior start
                let idx = message.parts.count
                toolPartIndices[tcId] = idx
                let part = ToolInvocationPart(
                    toolCallId: tcId,
                    toolName: toolName,
                    state: .inputAvailable,
                    input: input
                )
                message.parts.append(.toolInvocation(part))
            }

        case .toolOutputAvailable(let tcId, let output):
            guard let idx = toolPartIndices[tcId] else { return }
            if case .toolInvocation(var p) = message.parts[idx] {
                p.state = .outputAvailable
                p.output = output
                message.parts[idx] = .toolInvocation(p)
            }

        case .source(let id, let url, let title):
            message.parts.append(.sourceURL(SourceURLPart(id: id, url: url, title: title)))

        case .sources(let list):
            for src in list {
                message.parts.append(.sourceURL(src))
            }

        case .data(let name, let payload):
            message.parts.append(.data(DataPart(name: name, data: payload)))
        }
    }

    /// Convenience: apply an array of chunks in order.
    public mutating func applyAll(_ chunks: [UIMessageChunk]) {
        for chunk in chunks {
            apply(chunk)
        }
    }
}
