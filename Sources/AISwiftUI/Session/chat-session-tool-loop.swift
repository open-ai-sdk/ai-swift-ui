import Foundation

// MARK: - Tool loop extension for ChatSession

extension ChatSession {

    // MARK: - Constants

    /// Maximum automatic tool-call iterations per `send`/`regenerate` to prevent infinite loops.
    static let maxToolIterations = 10

    // MARK: - Public tool result API

    /// Record a tool output and, if `sendAutomaticallyWhen` approves, auto-resubmit.
    ///
    /// - Parameters:
    ///   - toolCallId: The ID of the tool call to update.
    ///   - output: The JSON result of the tool execution.
    ///   - errorText: When non-nil, the part state is set to `.outputError`.
    ///   - options: Optional per-request options forwarded to the re-submit.
    public func addToolResult(
        toolCallId: String,
        output: JSONValue,
        errorText: String? = nil,
        options: ChatRequestOptions? = nil
    ) async {
        updateToolPart(toolCallId: toolCallId) { part in
            part.state = errorText != nil ? .outputError : .outputAvailable
            part.output = output
        }
        await autoResubmitIfNeeded(options: options)
    }

    // MARK: - Internal helpers

    /// Mutate the `ToolInvocationPart` matching `toolCallId`. Scans from end (tool parts are in the last assistant message).
    func updateToolPart(toolCallId: String, mutation: (inout ToolInvocationPart) -> Void) {
        for msgIdx in messages.indices.reversed() {
            for partIdx in messages[msgIdx].parts.indices {
                if case .toolInvocation(var part) = messages[msgIdx].parts[partIdx],
                   part.toolCallId == toolCallId {
                    mutation(&part)
                    messages[msgIdx].parts[partIdx] = .toolInvocation(part)
                    return
                }
            }
        }
    }

    /// Re-submit to the assistant if `sendAutomaticallyWhen` approves and iteration budget allows.
    func autoResubmitIfNeeded(options: ChatRequestOptions?) async {
        guard let condition = sendAutomaticallyWhen else { return }
        guard toolIterationCount < ChatSession.maxToolIterations else { return }
        guard await condition(messages) else { return }
        guard status == .ready else { return }

        let assistantId = UUID().uuidString
        messages.append(UIMessage(id: assistantId, role: .assistant, parts: []))
        await streamAssistant(
            assistantId: assistantId,
            options: options,
            toolIteration: toolIterationCount + 1
        )
    }
}
