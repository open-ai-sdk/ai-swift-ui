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

// MARK: - Session Enhancements Tests

@MainActor
struct SessionEnhancementsTests {

    // MARK: - setMessages

    @Test func setMessagesReplacesArray() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "se-1", transport: transport)

        let newMessages = [
            UIMessage(id: "m1", role: .user, parts: [.text(TextPart(text: "Hello"))]),
            UIMessage(id: "m2", role: .assistant, parts: [.text(TextPart(text: "Hi there"))]),
        ]

        session.setMessages(newMessages)

        #expect(session.messages.count == 2)
        #expect(session.messages[0].id == "m1")
        #expect(session.messages[1].id == "m2")
    }

    @Test func setMessagesWithTransformModifiesArray() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "se-2", transport: transport)

        session.setMessages([UIMessage(id: "m1", role: .user, parts: [])])

        // Apply transform: append another message
        session.setMessages { messages in
            messages + [UIMessage(id: "m2", role: .assistant, parts: [])]
        }

        #expect(session.messages.count == 2)
        #expect(session.messages[1].id == "m2")
    }

    @Test func setMessagesBlockedDuringStreaming() async throws {
        let slowTransport = SlowEnhancementsTransport(
            chunks: makeTextChunks(msgId: "msg-block", text: "streaming"),
            delay: 0.05
        )
        let session = ChatSession(id: "se-3", transport: slowTransport)

        let sendTask = Task { @MainActor in
            await session.send(.user(text: "start streaming"))
        }
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms — session is now streaming

        // setMessages should be a no-op while streaming
        let replacement = [UIMessage(id: "injected", role: .user, parts: [])]
        session.setMessages(replacement)
        // Messages should NOT have been replaced
        #expect(!session.messages.contains { $0.id == "injected" })

        await sendTask.value
    }

    // MARK: - send(replacingMessageId:)

    @Test func sendReplacingMessageIdTruncatesAndResubmits() async throws {
        // Build a session with 4 messages via sequential sends
        let firstTransport = MockChatTransport(chunks: makeTextChunks(msgId: "a1", text: "Answer 1"))
        let session = ChatSession(id: "se-4", transport: firstTransport)
        await session.send(.user(text: "Q1"))
        #expect(session.messages.count == 2)

        let secondTransport = MockChatTransport(chunks: makeTextChunks(msgId: "a2", text: "Answer 2"))
        let session2 = ChatSession(id: "se-4", transport: secondTransport, messages: session.messages)
        await session2.send(.user(text: "Q2"))
        #expect(session2.messages.count == 4)

        // Now branch from the first user message
        let firstUserMessageId = session2.messages[0].id
        let branchTransport = MockChatTransport(chunks: makeTextChunks(msgId: "a-branch", text: "Branched"))
        let session3 = ChatSession(id: "se-4-branch", transport: branchTransport, messages: session2.messages)

        await session3.send(.user(text: "Q1-revised"), replacingMessageId: firstUserMessageId)

        // Should have replaced from that point: new user msg + new assistant msg = 2
        #expect(session3.messages.count == 2)
        #expect(session3.messages[0].primaryText == "Q1-revised")
        #expect(session3.messages[1].primaryText == "Branched")
    }

    @Test func sendReplacingNonExistentIdIsNoop() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "noop-msg", text: "answer"))
        let session = ChatSession(id: "se-5", transport: transport)
        await session.send(.user(text: "Q1"))
        let countBefore = session.messages.count

        // replacingMessageId doesn't exist
        await session.send(.user(text: "Q2"), replacingMessageId: "nonexistent-id")

        // Should not have changed (send is guarded by the id lookup)
        #expect(session.messages.count == countBefore)
    }

    // MARK: - resubmit

    @Test func resubmitSendsWithoutNewUserMessage() async throws {
        // Set up session with one user message
        let firstTransport = MockChatTransport(chunks: makeTextChunks(msgId: "r1", text: "First response"))
        let session = ChatSession(id: "se-6", transport: firstTransport)
        await session.send(.user(text: "Hello"))
        #expect(session.messages.count == 2)

        // Now resubmit using a new transport
        let resubmitTransport = MockChatTransport(chunks: makeTextChunks(msgId: "r2", text: "Resubmitted response"))
        let session2 = ChatSession(id: "se-6", transport: resubmitTransport, messages: session.messages)

        await session2.resubmit()

        // resubmit appends a new assistant message (does not add user message)
        // Original messages (2) + new assistant = 3
        #expect(session2.messages.count == 3)
        #expect(session2.messages.last?.role == .assistant)
        #expect(session2.messages.last?.primaryText == "Resubmitted response")
    }

    @Test func resubmitBlockedDuringStreaming() async throws {
        let slowTransport = SlowEnhancementsTransport(
            chunks: makeTextChunks(msgId: "resubmit-block", text: "streaming"),
            delay: 0.05
        )
        let session = ChatSession(id: "se-7", transport: slowTransport)

        let sendTask = Task { @MainActor in
            await session.send(.user(text: "start"))
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        // resubmit should be blocked while streaming
        let transport2 = MockChatTransport(chunks: makeTextChunks(msgId: "extra", text: "extra"))
        let _ = transport2  // intentionally unused
        await session.resubmit()  // should be no-op

        await sendTask.value
        // Status should still be ready after original stream completes
        #expect(session.status == .ready)
    }
}

// MARK: - SlowEnhancementsTransport

private struct SlowEnhancementsTransport: ChatTransport, Sendable {
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
