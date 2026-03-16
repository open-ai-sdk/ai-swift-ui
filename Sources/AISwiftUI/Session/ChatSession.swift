import Foundation
import Observation

/// The main SwiftUI-facing chat session object.
///
/// `ChatSession` manages the full lifecycle of a chat conversation:
/// optimistic user message appending, assistant response streaming,
/// cancellation, regeneration, tool-result round-trips, and error handling.
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
    public internal(set) var messages: [UIMessage]

    /// The current lifecycle status.
    public internal(set) var status: ChatStatus

    /// The last error, if `status == .error`.
    public internal(set) var error: (any Error)?

    /// The finish reason from the last completed stream (e.g. "stop", "length").
    public private(set) var finishReason: String?

    /// Set to `true` when the last stream was aborted.
    public private(set) var isAborted: Bool = false

    // MARK: - Callbacks

    /// Called when the assistant message is fully received.
    public var onFinish: ((UIMessage, String?) -> Void)?

    /// Called when a stream error occurs.
    public var onError: ((any Error) -> Void)?

    /// Called for each `data-*` chunk received.
    public var onDataPart: ((String, Any) -> Void)?

    /// Called when a tool part transitions to `.inputAvailable`.
    /// Return a `JSONValue` to auto-record the result; return `nil` to handle manually.
    public var onToolCall: ((ToolInvocationPart) async -> JSONValue?)?

    /// When set, evaluated after each `addToolResult`.
    /// If it returns `true` and status is `.ready`, the session auto-resubmits.
    public var sendAutomaticallyWhen: (([UIMessage]) async -> Bool)?

    /// Word-level smoothing delay. Set to enable smooth stream rendering.
    public var smoothStreamDelay: Duration?

    // MARK: - Attachments

    /// The uploader for pending attachments. Set to enable attachment pipeline.
    public var attachmentUploader: (any AttachmentUploader)?

    /// Attachments staged for the next send.
    public internal(set) var pendingAttachments: [PendingAttachment] = []

    // MARK: - Internal state

    let transport: any ChatTransport
    private var streamTask: Task<Void, Never>?

    /// Current tool-call iteration depth; reset to 0 on each `send`/`regenerate`.
    var toolIterationCount: Int = 0

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
    public func send(_ message: NewUIMessage, options: ChatRequestOptions? = nil) async {
        guard status == .ready || status == .error else { return }
        error = nil
        status = .submitted
        toolIterationCount = 0

        var outgoing = message
        if !pendingAttachments.isEmpty, let uploader = attachmentUploader {
            let toUpload = pendingAttachments
            pendingAttachments.removeAll()
            do {
                let uploaded = try await withThrowingTaskGroup(of: FilePart.self) { group in
                    for attachment in toUpload {
                        group.addTask { try await uploader.upload(attachment) }
                    }
                    var results: [FilePart] = []
                    for try await part in group { results.append(part) }
                    return results
                }
                outgoing.files += uploaded
            } catch {
                self.error = error
                self.status = .error
                onError?(error)
                return
            }
        }

        messages.append(outgoing.makeMessage())

        let assistantId = UUID().uuidString
        messages.append(UIMessage(id: assistantId, role: .assistant, parts: []))
        await streamAssistant(assistantId: assistantId, options: options, toolIteration: 0)
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

        while let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }
        guard messages.last?.role == .user else { return }

        error = nil
        status = .submitted
        toolIterationCount = 0

        let assistantId = UUID().uuidString
        messages.append(UIMessage(id: assistantId, role: .assistant, parts: []))
        await streamAssistant(assistantId: assistantId, options: options, toolIteration: 0)
    }

    /// Clear the current error and reset status to `.ready`.
    public func clearError() {
        error = nil
        if status == .error { status = .ready }
    }

    // MARK: - Internal streaming

    func streamAssistant(assistantId: String, options: ChatRequestOptions?, toolIteration: Int) async {
        toolIterationCount = toolIteration
        let request = TransportSendRequest(id: id, messages: messages, options: options)
        var reducer = UIMessageStreamReducer(messageId: assistantId)
        var currentAssistantId = assistantId
        // Cache the assistant message index to avoid O(n) scan per chunk
        let assistantIdx = messages.count - 1

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                await MainActor.run { self.status = .streaming }
                let rawStream = transport.send(request)
                let stream: AsyncThrowingStream<UIMessageChunk, any Error>
                if let delay = smoothStreamDelay {
                    stream = smoothStream(rawStream, delay: delay)
                } else {
                    stream = rawStream
                }
                let shouldTrackTools = self.onToolCall != nil && toolIteration < ChatSession.maxToolIterations
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if case .start(let serverId, _) = chunk {
                            if assistantIdx < self.messages.count, self.messages[assistantIdx].id == currentAssistantId {
                                let old = self.messages[assistantIdx]
                                self.messages[assistantIdx] = UIMessage(
                                    id: serverId, role: old.role,
                                    parts: old.parts, createdAt: old.createdAt
                                )
                            }
                            currentAssistantId = serverId
                            reducer = UIMessageStreamReducer(messageId: serverId)
                        }

                        // Snapshot tool state only when tracking tools (avoids hot-path alloc)
                        let prevInputAvailable: Set<String>?
                        if shouldTrackTools {
                            prevInputAvailable = Set(
                                reducer.message.toolInvocations
                                    .filter { $0.state == .inputAvailable }
                                    .map { $0.toolCallId }
                            )
                        } else {
                            prevInputAvailable = nil
                        }

                        reducer.apply(chunk)
                        // Direct index update instead of linear scan
                        if assistantIdx < self.messages.count {
                            self.messages[assistantIdx] = reducer.message
                        }

                        if case .data(let name, let payload, _, _) = chunk {
                            self.onDataPart?(name, payload.rawValue)
                        }
                        if case .abort(let reason) = chunk {
                            self.isAborted = true
                            let err = AbortError(reason: reason)
                            self.error = err
                            self.onError?(err)
                        }

                        // Fire onToolCall for newly inputAvailable parts
                        guard let prev = prevInputAvailable else { return }
                        let newlyReady = reducer.message.toolInvocations.filter {
                            $0.state == .inputAvailable && !prev.contains($0.toolCallId)
                        }
                        guard !newlyReady.isEmpty else { return }
                        Task {
                            for tip in newlyReady {
                                if let result = await self.onToolCall?(tip) {
                                    await self.addToolResult(toolCallId: tip.toolCallId, output: result, options: options)
                                }
                            }
                        }
                    }
                }
                await MainActor.run {
                    if !Task.isCancelled {
                        self.finalizeStream(assistantId: currentAssistantId, reducer: reducer)
                    }
                }
            } catch {
                await MainActor.run { self.handleStreamError(error, assistantId: currentAssistantId) }
            }
        }

        streamTask = task
        await task.value
        streamTask = nil
    }

    private func finalizeStream(assistantId: String, reducer: UIMessageStreamReducer) {
        finishReason = reducer.finishReason
        isAborted = reducer.isAborted
        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            onFinish?(messages[idx], reducer.finishReason)
        }
        status = .ready
    }

    private func handleStreamError(_ streamError: any Error, assistantId: String) {
        // Log the concrete error type and description for diagnostics.
        let nsError = streamError as NSError
        print("[ChatSession] Stream error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription) type=\(type(of: streamError))")
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

// MARK: - AbortError

/// Emitted when an `abort` chunk is received from the server.
public struct AbortError: Error, Sendable, CustomStringConvertible {
    public let reason: String?
    public var description: String { reason ?? "Stream aborted by server" }
}
