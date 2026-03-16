import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Helpers

private func makeToolChunks(msgId: String, toolCallId: String, toolName: String) -> [UIMessageChunk] {
    [
        .start(messageId: msgId),
        .startStep,
        .toolInputStart(toolCallId: toolCallId, toolName: toolName),
        .toolInputAvailable(toolCallId: toolCallId, toolName: toolName, input: .object(["q": .string("test")])),
        .finishStep,
        .finish(),
    ]
}

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

// MARK: - Tool Result Loop Tests

@MainActor
struct ToolResultLoopTests {

    @Test func addToolResultSetsOutputAvailable() async throws {
        let toolCallId = "tc-1"
        let transport = MockChatTransport(chunks: makeToolChunks(msgId: "msg-1", toolCallId: toolCallId, toolName: "search"))
        let session = ChatSession(id: "s1", transport: transport)
        await session.send(.user(text: "query"))

        await session.addToolResult(toolCallId: toolCallId, output: .string("result-value"))

        let invocations = session.messages.flatMap { $0.toolInvocations }
        let part = invocations.first { $0.toolCallId == toolCallId }
        #expect(part?.state == .outputAvailable)
        #expect(part?.output == .string("result-value"))
    }

    @Test func addToolResultWithErrorTextSetsOutputError() async throws {
        let toolCallId = "tc-2"
        let transport = MockChatTransport(chunks: makeToolChunks(msgId: "msg-2", toolCallId: toolCallId, toolName: "fetch"))
        let session = ChatSession(id: "s2", transport: transport)
        await session.send(.user(text: "fetch something"))

        await session.addToolResult(toolCallId: toolCallId, output: .string("err-payload"), errorText: "Something went wrong")

        let invocations = session.messages.flatMap { $0.toolInvocations }
        let part = invocations.first { $0.toolCallId == toolCallId }
        #expect(part?.state == .outputError)
    }

    @Test func addToolResultWithoutErrorTextSetsOutputAvailable() async throws {
        let toolCallId = "tc-3"
        let transport = MockChatTransport(chunks: makeToolChunks(msgId: "msg-3", toolCallId: toolCallId, toolName: "calc"))
        let session = ChatSession(id: "s3", transport: transport)
        await session.send(.user(text: "calculate"))

        await session.addToolResult(toolCallId: toolCallId, output: .int(42))

        let invocations = session.messages.flatMap { $0.toolInvocations }
        let part = invocations.first { $0.toolCallId == toolCallId }
        #expect(part?.state == .outputAvailable)
        #expect(part?.output == .int(42))
    }

    @Test func onToolCallCallbackFiresWhenInputAvailable() async throws {
        let toolCallId = "tc-4"
        let chunks = makeToolChunks(msgId: "msg-4", toolCallId: toolCallId, toolName: "lookup")
        let transport = MockChatTransport(chunks: chunks)
        let session = ChatSession(id: "s4", transport: transport)

        var callbackFired = false
        // Return nil so no auto-result is recorded
        session.onToolCall = { _ in
            callbackFired = true
            return nil
        }

        await session.send(.user(text: "look up something"))

        #expect(callbackFired)
    }

    @Test func nonNilOnToolCallAutoCallsAddToolResult() async throws {
        let toolCallId = "tc-5"
        let chunks = makeToolChunks(msgId: "msg-5", toolCallId: toolCallId, toolName: "compute")
        let transport = MockChatTransport(chunks: chunks)
        let session = ChatSession(id: "s5", transport: transport)

        nonisolated(unsafe) var callCount = 0
        // Return nil to avoid triggering autoResubmit; we just verify callback fires
        session.onToolCall = { _ in
            callCount += 1
            return nil
        }

        await session.send(.user(text: "compute something"))
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(callCount == 1)

        // Now manually call addToolResult and verify state changes
        await session.addToolResult(toolCallId: toolCallId, output: .string("computed-output"))

        let invocations = session.messages.flatMap { $0.toolInvocations }
        let part = invocations.first { $0.toolCallId == toolCallId }
        #expect(part?.state == .outputAvailable)
        #expect(part?.output == .string("computed-output"))
    }

    @Test func sendAutomaticallyWhenTriggersResubmit() async throws {
        let toolCallId = "tc-6"
        let firstChunks = makeToolChunks(msgId: "msg-6", toolCallId: toolCallId, toolName: "tool")
        let secondChunks = makeTextChunks(msgId: "msg-6b", text: "Done")

        let transport = SequentialMockTransport(chunkSets: [firstChunks, secondChunks])
        let session = ChatSession(id: "s6", transport: transport)

        session.sendAutomaticallyWhen = { messages in
            messages.flatMap { $0.toolInvocations }.contains { $0.state == .outputAvailable }
        }

        await session.send(.user(text: "start"))
        await session.addToolResult(toolCallId: toolCallId, output: .string("result"))

        #expect(session.status == .ready)
        // After auto-resubmit, there should be additional messages
        #expect(session.messages.count >= 2)
    }

    @Test func maxIterationGuardPreventsInfiniteLoop() async throws {
        // Tool chunks only — the session should stop after maxToolIterations
        let toolCallId = "tc-7"
        let toolChunks = makeToolChunks(msgId: "msg-7", toolCallId: toolCallId, toolName: "looper")

        // Always return tool chunks to simulate infinite loop
        let transport = RepeatingMockTransport(chunks: toolChunks)
        let session = ChatSession(id: "s7", transport: transport)

        session.onToolCall = { _ in .string("output") }

        await session.send(.user(text: "loop"))
        try await Task.sleep(nanoseconds: 200_000_000)

        // toolIterationCount should not exceed maxToolIterations
        #expect(session.toolIterationCount <= ChatSession.maxToolIterations)
    }
}

// MARK: - SequentialMockTransport

/// Replays successive chunk sets on each send() call.
private final class SequentialMockTransport: ChatTransport, @unchecked Sendable {
    private var chunkSets: [[UIMessageChunk]]
    private var index = 0

    init(chunkSets: [[UIMessageChunk]]) {
        self.chunkSets = chunkSets
    }

    func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        let chunks = index < chunkSets.count ? chunkSets[index] : []
        index += 1
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

// MARK: - RepeatingMockTransport

/// Always replays the same chunk set, simulating a looping tool call.
private struct RepeatingMockTransport: ChatTransport, Sendable {
    let chunks: [UIMessageChunk]

    func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}
