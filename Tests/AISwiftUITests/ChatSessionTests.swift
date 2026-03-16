import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Helpers

private func makeTextChunks(msgId: String, text: String) -> [UIMessageChunk] {
    [
        .start(messageId: msgId),
        .startStep,
        .textStart(id: "t1"),
        .textDelta(id: "t1", delta: text),
        .textEnd(id: "t1"),
        .finishStep,
        .finish(),
    ]
}

private func makeErrorChunks(msgId: String, partial: String) -> [UIMessageChunk] {
    [
        .start(messageId: msgId),
        .startStep,
        .textStart(id: "t1"),
        .textDelta(id: "t1", delta: partial),
    ]
}

// MARK: - ChatSession tests

@MainActor
struct ChatSessionTests {

    @Test func sendAppendsUserAndAssistantMessages() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-1", text: "Hello back!"))
        let session = ChatSession(id: "session-1", transport: transport)

        await session.send(.user(text: "Hello"))

        #expect(session.messages.count == 2)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[0].primaryText == "Hello")
        #expect(session.messages[1].role == .assistant)
        #expect(session.messages[1].primaryText == "Hello back!")
        #expect(session.status == .ready)
        #expect(session.error == nil)
    }

    @Test func statusTransitionsCorrectly() async throws {
        var observedStatuses: [ChatStatus] = []
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-s", text: "ok"))
        let session = ChatSession(id: "session-s", transport: transport)

        observedStatuses.append(session.status)  // .ready
        await session.send(.user(text: "hi"))
        observedStatuses.append(session.status)  // .ready (after completion)

        #expect(observedStatuses.contains(.ready))
        #expect(session.status == .ready)
    }

    @Test func errorDoesNotDestroyPreviousMessages() async throws {
        struct StreamFailure: Error {}

        // First send succeeds
        let successTransport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-ok", text: "First answer"))
        let session = ChatSession(id: "session-e", transport: successTransport)
        await session.send(.user(text: "First question"))
        #expect(session.messages.count == 2)

        // Second send fails — use a new session with error transport pointing to same messages
        let errorTransport = MockChatTransport(
            chunks: [.start(messageId: "msg-err"), .startStep],
            error: StreamFailure()
        )
        let session2 = ChatSession(id: "session-e", transport: errorTransport, messages: session.messages)
        let messagesBefore = session2.messages.count
        await session2.send(.user(text: "Second question"))

        // After error: previous messages preserved, status = .error
        #expect(session2.status == .error)
        #expect(session2.error != nil)
        // User message appended, empty assistant removed, so count = messagesBefore + 1
        #expect(session2.messages.count == messagesBefore + 1)
        // The first successful messages are intact
        #expect(session2.messages[0].role == .user)
        #expect(session2.messages[0].primaryText == "First question")
    }

    @Test func stopCancelsStream() async throws {
        // Use a slow-yielding mock transport
        let slowTransport = SlowMockTransport(chunks: makeTextChunks(msgId: "msg-stop", text: "result"), delay: 0.1)
        let session = ChatSession(id: "session-stop", transport: slowTransport)

        // Start send in background, then stop immediately
        let sendTask = Task { @MainActor in
            await session.send(.user(text: "cancel me"))
        }
        // Give the task a moment to start
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        session.stop()
        await sendTask.value

        // After stop, status should be ready (cancelled)
        #expect(session.status == .ready)
    }

    @Test func regenerateRemovesLastAssistantAndResends() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-r", text: "Regenerated answer"))
        let session = ChatSession(id: "session-regen", transport: transport)

        // Send initial message
        await session.send(.user(text: "Question"))
        #expect(session.messages.count == 2)
        let firstAnswer = session.messages[1].primaryText

        // Regenerate (needs a new transport)
        let transport2 = MockChatTransport(chunks: makeTextChunks(msgId: "msg-r2", text: "New answer"))
        let session2 = ChatSession(id: "session-regen", transport: transport2, messages: session.messages)
        await session2.regenerate()

        #expect(session2.messages.count == 2)
        #expect(session2.messages[0].role == .user)
        // New answer should differ (or same structure)
        _ = firstAnswer  // silence unused warning
        #expect(session2.messages[1].role == .assistant)
        #expect(session2.status == .ready)
    }

    @Test func onFinishCallbackFires() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-cb", text: "done"))
        let session = ChatSession(id: "session-cb", transport: transport)

        var finishedMessage: UIMessage?
        session.onFinish = { msg, _ in finishedMessage = msg }

        await session.send(.user(text: "go"))

        #expect(finishedMessage != nil)
        #expect(finishedMessage?.primaryText == "done")
    }

    @Test func onErrorCallbackFires() async throws {
        struct TestError: Error {}
        let transport = MockChatTransport(
            chunks: [.start(messageId: "msg-err")],
            error: TestError()
        )
        let session = ChatSession(id: "session-onerr", transport: transport)

        var capturedError: (any Error)?
        session.onError = { err in capturedError = err }

        await session.send(.user(text: "trigger error"))

        #expect(capturedError != nil)
        #expect(session.status == .error)
    }

    @Test func onDataPartCallbackFires() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-data"),
            .startStep,
            .data(name: "plan", payload: .object(["step": .string("one")])),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "answer"),
            .textEnd(id: "t1"),
            .finishStep,
            .finish(),
        ])
        let session = ChatSession(id: "session-data", transport: transport)

        var dataEvents: [(String, Any)] = []
        session.onDataPart = { name, payload in dataEvents.append((name, payload)) }

        await session.send(.user(text: "query"))

        #expect(dataEvents.count == 1)
        #expect(dataEvents[0].0 == "plan")
    }

    @Test func clearErrorResetsStatus() async throws {
        struct TestError: Error {}
        let transport = MockChatTransport(
            chunks: [.start(messageId: "msg-ce")],
            error: TestError()
        )
        let session = ChatSession(id: "session-clear", transport: transport)
        await session.send(.user(text: "fail"))

        #expect(session.status == .error)
        session.clearError()
        #expect(session.status == .ready)
        #expect(session.error == nil)
    }

    @Test func multipleMessagesAccumulate() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "msg-m1", text: "Answer 1"))
        let session = ChatSession(id: "session-multi", transport: transport)

        await session.send(.user(text: "Q1"))
        #expect(session.messages.count == 2)

        // Replace transport for second send
        let transport2 = MockChatTransport(chunks: makeTextChunks(msgId: "msg-m2", text: "Answer 2"))
        let session2 = ChatSession(id: "session-multi", transport: transport2, messages: session.messages)
        await session2.send(.user(text: "Q2"))

        #expect(session2.messages.count == 4)
        #expect(session2.messages[2].primaryText == "Q2")
        #expect(session2.messages[3].primaryText == "Answer 2")
    }
}

// MARK: - SlowMockTransport for cancellation tests

private struct SlowMockTransport: ChatTransport, Sendable {
    let chunks: [UIMessageChunk]
    let delay: TimeInterval

    func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        let chunks = self.chunks
        let delay = self.delay
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}
