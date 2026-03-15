import Foundation
import Observation

/// The main SwiftUI-facing chat session object.
///
/// `ChatSession` manages the full lifecycle of a chat conversation:
/// optimistic user message appending, assistant response streaming,
/// cancellation, regeneration, and error handling.
///
/// Observe `messages`, `status`, and `error` from SwiftUI views.
///
/// ```swift
/// let session = ChatSession(id: conversationID, transport: transport)
/// await session.send(.user(text: "Hello"))
/// ```
@MainActor
@Observable
public final class ChatSession: Identifiable {

    // MARK: - Public Observable State

    public let id: String

    /// The ordered list of messages in the conversation.
    public private(set) var messages: [UIMessage]

    /// The current lifecycle status.
    public private(set) var status: ChatStatus

    /// The last error, if `status == .error`.
    public private(set) var error: (any Error)?

    // MARK: - Callbacks

    /// Called when the assistant message is fully received.
    public var onFinish: ((UIMessage) -> Void)?

    /// Called when a stream error occurs.
    public var onError: ((any Error) -> Void)?

    /// Called for each `data-*` chunk received.
    /// Parameters: chunk name, raw payload.
    public var onDataPart: ((String, Any) -> Void)?

    // MARK: - Private state

    private let transport: any ChatTransport
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        id: String,
        transport: any ChatTransport,
        messages: [UIMessage] = []
    ) {
        self.id = id
        self.transport = transport
        self.messages = messages
        self.status = .ready
    }

    // MARK: - Public API

    /// Send a new user message and start streaming the assistant response.
    ///
    /// - Parameters:
    ///   - message: The user message to append.
    ///   - options: Optional per-request options (headers, body, metadata).
    public func send(_ message: NewUIMessage, options: ChatRequestOptions? = nil) async {
        guard status == .ready || status == .error else { return }

        // Clear previous error state
        error = nil
        status = .submitted

        // Optimistically append user message
        let userMsg = message.makeMessage()
        messages.append(userMsg)

        // Create assistant placeholder
        let assistantId = UUID().uuidString
        let placeholder = UIMessage(id: assistantId, role: .assistant, parts: [])
        messages.append(placeholder)

        await streamAssistant(assistantId: assistantId, options: options)
    }

    /// Stop the current stream. Status will return to `.ready`.
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if status == .streaming || status == .submitted {
            status = .ready
        }
    }

    /// Remove the last assistant message and re-send the last user message.
    public func regenerate(options: ChatRequestOptions? = nil) async {
        guard status == .ready || status == .error else { return }

        // Remove trailing assistant message(s)
        while let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }
        guard let lastUser = messages.last, lastUser.role == .user else { return }

        error = nil
        status = .submitted

        // Re-append assistant placeholder
        let assistantId = UUID().uuidString
        let placeholder = UIMessage(id: assistantId, role: .assistant, parts: [])
        messages.append(placeholder)

        await streamAssistant(assistantId: assistantId, options: options)
    }

    /// Clear the current error and reset status to `.ready`.
    public func clearError() {
        error = nil
        if status == .error {
            status = .ready
        }
    }

    // MARK: - Private streaming

    private func streamAssistant(assistantId: String, options: ChatRequestOptions?) async {
        let request = TransportSendRequest(id: id, messages: messages, options: options)
        var reducer = UIMessageStreamReducer(messageId: assistantId)
        // Track current assistant message ID (may change if server assigns new ID via start chunk)
        var currentAssistantId = assistantId

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                await MainActor.run { self.status = .streaming }
                for try await chunk in transport.send(request) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        // Handle start chunk: server may assign a different message ID
                        if case .start(let serverId) = chunk {
                            // Rename the placeholder to the server-assigned ID
                            if let idx = self.messages.firstIndex(where: { $0.id == currentAssistantId }) {
                                var renamed = self.messages[idx]
                                renamed = UIMessage(id: serverId, role: renamed.role, parts: renamed.parts, createdAt: renamed.createdAt)
                                self.messages[idx] = renamed
                            }
                            currentAssistantId = serverId
                            reducer = UIMessageStreamReducer(messageId: serverId)
                            return
                        }

                        reducer.apply(chunk)
                        self.updateAssistantMessage(reducer.message, id: currentAssistantId)

                        // Fire onDataPart callback for data chunks
                        if case .data(let name, let payload) = chunk {
                            self.onDataPart?(name, payload.rawValue)
                        }
                    }
                }
                await MainActor.run {
                    if !Task.isCancelled {
                        self.finalizeStream(assistantId: currentAssistantId, reducer: reducer)
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleStreamError(error, assistantId: currentAssistantId)
                }
            }
        }

        streamTask = task
        await task.value
        streamTask = nil
    }

    private func updateAssistantMessage(_ message: UIMessage, id: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx] = message
    }

    private func finalizeStream(assistantId: String, reducer: UIMessageStreamReducer) {
        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            onFinish?(messages[idx])
        }
        status = .ready
    }

    private func handleStreamError(_ streamError: any Error, assistantId: String) {
        // Remove the empty assistant placeholder if it has no content
        if let idx = messages.firstIndex(where: { $0.id == assistantId }),
           messages[idx].primaryText.isEmpty,
           messages[idx].toolInvocations.isEmpty {
            messages.remove(at: idx)
        }
        error = streamError
        status = .error
        onError?(streamError)
    }
}
