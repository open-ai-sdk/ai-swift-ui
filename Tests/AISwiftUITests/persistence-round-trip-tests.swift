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

private func makeSampleMessages() -> [UIMessage] {
    [
        UIMessage(
            id: "msg-u1",
            role: .user,
            parts: [.text(TextPart(text: "Hello assistant"))],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            metadata: nil
        ),
        UIMessage(
            id: "msg-a1",
            role: .assistant,
            parts: [.text(TextPart(text: "Hello user"))],
            createdAt: Date(timeIntervalSince1970: 1_000_001),
            metadata: ["model": .string("gpt-4o")]
        ),
    ]
}

// MARK: - Persistence Round-Trip Tests

struct PersistenceRoundTripTests {

    @Test func messagesSurviveEncodeDecodeRoundTrip() throws {
        let original = makeSampleMessages()
        let data = try original.jsonData()
        let restored = try [UIMessage](jsonData: data)

        #expect(restored.count == original.count)
        for (orig, rest) in zip(original, restored) {
            #expect(orig.id == rest.id)
            #expect(orig.role == rest.role)
            #expect(orig.primaryText == rest.primaryText)
        }
    }

    @Test func messageMetadataSurvivesRoundTrip() throws {
        let original = [
            UIMessage(
                id: "m1",
                role: .assistant,
                parts: [.text(TextPart(text: "answer"))],
                metadata: ["model": .string("claude-3"), "tokens": .int(42)]
            )
        ]
        let data = try original.jsonData()
        let restored = try [UIMessage](jsonData: data)

        #expect(restored[0].metadata?["model"]?.stringValue == "claude-3")
        #expect(restored[0].metadata?["tokens"]?.intValue == 42)
    }

    @Test func persistablePartsFiltersTransientDataParts() {
        let transientData = DataPart(name: "usage", data: .object([:]), isTransient: true)
        let persistentData = DataPart(name: "plan", data: .string("step 1"), isTransient: false)
        let msg = UIMessage(
            id: "m1",
            role: .assistant,
            parts: [
                .text(TextPart(text: "answer")),
                .data(transientData),
                .data(persistentData),
            ]
        )

        let persistable = msg.persistableParts
        #expect(persistable.count == 2)
        // Should contain text and non-transient data, but not transient data
        let hasTransient = persistable.contains {
            if case .data(let dp) = $0, dp.isTransient { return true }
            return false
        }
        #expect(!hasTransient)
    }

    @Test func persistablePartsKeepsAllNonDataParts() {
        let msg = UIMessage(
            id: "m1",
            role: .assistant,
            parts: [
                .text(TextPart(text: "answer")),
                .sourceURL(SourceURLPart(url: "https://example.com", title: "Example")),
            ]
        )

        let persistable = msg.persistableParts
        #expect(persistable.count == 2)
    }

    @Test func toolInvocationPartSurvivesRoundTrip() throws {
        let tool = ToolInvocationPart(
            toolCallId: "tc-1",
            toolName: "search",
            state: .outputAvailable,
            input: .object(["q": .string("swift")]),
            output: .object(["results": .array([.string("item1")])])
        )
        let msg = UIMessage(id: "m1", role: .assistant, parts: [.toolInvocation(tool)])
        let data = try [msg].jsonData()
        let restored = try [UIMessage](jsonData: data)

        #expect(restored[0].toolInvocations.count == 1)
        let restoredTool = restored[0].toolInvocations[0]
        #expect(restoredTool.toolCallId == "tc-1")
        #expect(restoredTool.toolName == "search")
        #expect(restoredTool.state == .outputAvailable)
        #expect(restoredTool.input == .object(["q": .string("swift")]))
    }
}

// MARK: - Snapshot/Restore on ChatSession Tests

@MainActor
struct ChatSessionSnapshotTests {

    @Test func snapshotRestoreRoundTrip() async throws {
        let transport = MockChatTransport(chunks: makeTextChunks(msgId: "snap-1", text: "Snapshot answer"))
        let session = ChatSession(id: "snap-session", transport: transport)
        await session.send(.user(text: "Snapshot question"))

        let data = try session.snapshot()
        #expect(!data.isEmpty)

        // Create new session and restore
        let transport2 = MockChatTransport(chunks: [])
        let session2 = ChatSession(id: "snap-session-2", transport: transport2)
        try session2.restore(from: data)

        #expect(session2.messages.count == session.messages.count)
        #expect(session2.messages[0].primaryText == "Snapshot question")
        #expect(session2.messages[1].primaryText == "Snapshot answer")
    }

    @Test func restoreBlockedDuringStreaming() async throws {
        let slowTransport = SlowPersistenceTransport(
            chunks: makeTextChunks(msgId: "block-restore", text: "streaming"),
            delay: 0.05
        )
        let session = ChatSession(id: "restore-block", transport: slowTransport)

        let extraMsg = [UIMessage(id: "injected", role: .user, parts: [])]
        let injectedData = try extraMsg.jsonData()

        let sendTask = Task { @MainActor in
            await session.send(.user(text: "start"))
        }
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms — streaming now

        // restore should be blocked
        try? session.restore(from: injectedData)
        #expect(!session.messages.contains { $0.id == "injected" })

        await sendTask.value
    }

    @Test func restoreWithInvalidDataThrows() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "restore-err", transport: transport)
        let badData = Data("not-json".utf8)

        #expect(throws: (any Error).self) {
            try session.restore(from: badData)
        }
    }
}

// MARK: - SlowPersistenceTransport

private struct SlowPersistenceTransport: ChatTransport, Sendable {
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
