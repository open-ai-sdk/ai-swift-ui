import Foundation

// MARK: - Session enhancements: setMessages, editing, resubmit, attachments, resumeStream

extension ChatSession {

    // MARK: - setMessages

    /// Replace messages externally (e.g. loading from persistence).
    public func setMessages(_ newMessages: [UIMessage]) {
        guard status == .ready || status == .error else { return }
        messages = newMessages
    }

    /// Functionally transform the message array.
    public func setMessages(_ transform: ([UIMessage]) -> [UIMessage]) {
        guard status == .ready || status == .error else { return }
        messages = transform(messages)
    }

    // MARK: - Message editing

    /// Replace a user message and resubmit from that point (conversation branching).
    public func send(
        _ message: NewUIMessage,
        replacingMessageId: String,
        options: ChatRequestOptions? = nil
    ) async {
        guard status == .ready || status == .error else { return }
        guard let idx = messages.firstIndex(where: { $0.id == replacingMessageId }) else { return }
        messages.removeSubrange(idx...)
        await send(message, options: options)
    }

    // MARK: - Resubmit

    /// Resubmit the current conversation without adding a new user message.
    public func resubmit(options: ChatRequestOptions? = nil) async {
        await prepareAndStream(options: options)
    }

    // MARK: - Attachments

    /// Add a file attachment from raw data.
    public func addAttachment(data: Data, filename: String, mimeType: String) {
        pendingAttachments.append(PendingAttachment(data: data, filename: filename, mimeType: mimeType))
    }

    /// Remove a pending attachment by ID.
    public func removeAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Clear all pending attachments.
    public func clearAttachments() {
        pendingAttachments.removeAll()
    }

    // MARK: - Resume stream

    /// Attempt to reconnect to an in-progress stream. No-op if transport doesn't support it.
    public func resumeStream(options: ChatRequestOptions? = nil) async {
        let request = TransportSendRequest(id: id, messages: messages, options: options)
        guard transport.reconnectToStream(request) != nil else { return }
        await prepareAndStream(options: options)
    }

    // MARK: - Snapshot / restore

    /// Encode current messages for storage.
    public func snapshot() throws -> Data {
        try messages.jsonData()
    }

    /// Restore messages from persisted data.
    public func restore(from data: Data) throws {
        guard status == .ready || status == .error else { return }
        messages = try [UIMessage](jsonData: data)
    }

    // MARK: - Internal

    /// Shared setup for resubmit/resumeStream: guard state, create placeholder, stream.
    func prepareAndStream(options: ChatRequestOptions?) async {
        guard status == .ready || status == .error else { return }
        error = nil
        status = .submitted
        toolIterationCount = 0
        let assistantId = UUID().uuidString
        messages.append(UIMessage(id: assistantId, role: .assistant, parts: []))
        await streamAssistant(assistantId: assistantId, options: options, toolIteration: 0)
    }
}
