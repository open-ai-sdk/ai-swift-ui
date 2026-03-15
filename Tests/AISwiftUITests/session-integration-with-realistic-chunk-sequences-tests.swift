import Testing
import Foundation
@testable import AISwiftUI

// MARK: - ChatSession integration tests using realistic chunk sequences from the backend contract

@MainActor
struct SessionIntegrationWithRealisticChunkSequencesTests {

    // MARK: - Full text-only stream

    @Test func sessionAssemblesTextOnlyStream() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-text-001"),
            .startStep,
            .textStart(id: "text_1"),
            .textDelta(id: "text_1", delta: "Hello! "),
            .textDelta(id: "text_1", delta: "How can I help you today?"),
            .textEnd(id: "text_1"),
            .finishStep,
            .finish,
        ])
        let session = ChatSession(id: "sess-text", transport: transport)
        await session.send(.user(text: "Hi"))

        #expect(session.status == .ready)
        #expect(session.error == nil)
        let assistant = session.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.primaryText == "Hello! How can I help you today?")
        #expect(assistant?.id == "msg-text-001")
    }

    // MARK: - Reasoning + text stream

    @Test func sessionAssemblesReasoningAndTextStream() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-reasoning"),
            .startStep,
            .reasoningStart(id: "r1"),
            .reasoningDelta(id: "r1", delta: "Let me think..."),
            .reasoningDelta(id: "r1", delta: " analyzing the question."),
            .reasoningEnd(id: "r1", signature: nil),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "The answer is 42."),
            .textEnd(id: "t1"),
            .finishStep,
            .finish,
        ])
        let session = ChatSession(id: "sess-reasoning", transport: transport)
        await session.send(.user(text: "What is the answer?"))

        let assistant = session.messages.last!
        #expect(assistant.primaryText == "The answer is 42.")

        let parts = assistant.parts
        #expect(parts.count == 2)
        guard case .reasoning(let rp) = parts[0] else {
            Issue.record("Expected reasoning part first"); return
        }
        #expect(rp.reasoning == "Let me think... analyzing the question.")
        #expect(rp.signature == nil)
    }

    // MARK: - Tool call + document references + usage stream

    @Test func sessionAssemblesToolCallWithDocumentReferencesAndUsage() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-tool-001"),
            .startStep,
            .toolInputStart(toolCallId: "tc-abc", toolName: "search_documents"),
            .toolInputDelta(toolCallId: "tc-abc", inputTextDelta: "{\"query\":\"Go concurrency\"}"),
            .toolInputAvailable(toolCallId: "tc-abc", toolName: "search_documents",
                                input: .object(["query": .string("Go concurrency")])),
            .toolOutputAvailable(toolCallId: "tc-abc",
                                 output: .object(["results": .array([.string("doc-1"), .string("doc-2")])])),
            .data(name: "document-references", payload: .array([
                .object(["id": .string("doc-1"), "title": .string("Concurrency in Go")]),
                .object(["id": .string("doc-2"), "title": .string("Go Patterns")]),
            ])),
            .finishStep,
            .startStep,
            .textStart(id: "text_2"),
            .textDelta(id: "text_2", delta: "Based on the documents, Go uses goroutines."),
            .textEnd(id: "text_2"),
            .finishStep,
            .data(name: "usage", payload: .object([
                "promptTokens": .int(120),
                "completionTokens": .int(45),
                "totalTokens": .int(165),
            ])),
            .finish,
        ])
        let session = ChatSession(id: "sess-tool", transport: transport)
        await session.send(.user(text: "Explain Go concurrency"))

        let assistant = session.messages.last!
        #expect(assistant.primaryText == "Based on the documents, Go uses goroutines.")

        // Tool invocation
        #expect(assistant.toolInvocations.count == 1)
        #expect(assistant.toolInvocations[0].toolCallId == "tc-abc")
        #expect(assistant.toolInvocations[0].toolName == "search_documents")
        #expect(assistant.toolInvocations[0].state == .outputAvailable)

        // Document references promoted to sourceDocument parts
        let docRefs = assistant.documentReferences
        #expect(docRefs.count == 2)
        #expect(docRefs[0].id == "doc-1")
        #expect(docRefs[0].title == "Concurrency in Go")

        // Usage tokens
        let usage = assistant.usageTokens
        #expect(usage?.promptTokens == 120)
        #expect(usage?.completionTokens == 45)
        #expect(usage?.totalTokens == 165)

        #expect(session.status == .ready)
    }

    // MARK: - Deep thinking: plan + steps + reasoning + tool + text + sources + suggested questions

    @Test func sessionAssemblesDeepThinkingStream() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-deep"),
            .data(name: "plan", payload: .object(["content": .string("Research, analyze, summarize.")])),
            .data(name: "steps", payload: .object(["steps": .array([.string("Search"), .string("Analyze"), .string("Write")])])),
            .startStep,
            .reasoningStart(id: "r1"),
            .reasoningDelta(id: "r1", delta: "I need to search for recent AI news."),
            .reasoningEnd(id: "r1", signature: nil),
            .toolInputStart(toolCallId: "ws-1", toolName: "web_search"),
            .toolInputAvailable(toolCallId: "ws-1", toolName: "web_search",
                                input: .object(["query": .string("latest AI 2025")])),
            .toolOutputAvailable(toolCallId: "ws-1",
                                 output: .object(["results": .array([.string("GPT-5"), .string("Gemini 2.0")])])),
            .finishStep,
            .startStep,
            .textStart(id: "text_2"),
            .textDelta(id: "text_2", delta: "The AI landscape in 2025 has seen remarkable progress."),
            .textEnd(id: "text_2"),
            .finishStep,
            .source(id: "s1", url: "https://openai.com/gpt5", title: "GPT-5 Announcement"),
            .sources([
                SourceURLPart(id: "s1", url: "https://openai.com/gpt5", title: "GPT-5 Announcement"),
                SourceURLPart(id: "s2", url: "https://deepmind.google/gemini", title: "Gemini 2.0 Ultra"),
            ]),
            .data(name: "suggested-questions", payload: .object([
                "questions": .array([
                    .string("How does GPT-5 compare to Gemini 2.0?"),
                    .string("What are the main use cases for Claude 4?"),
                ]),
            ])),
            .data(name: "usage", payload: .object([
                "promptTokens": .int(250),
                "completionTokens": .int(89),
                "totalTokens": .int(339),
            ])),
            .finish,
        ])
        let session = ChatSession(id: "sess-deep", transport: transport)
        await session.send(.user(text: "What happened in AI in 2025?"))

        let assistant = session.messages.last!
        #expect(assistant.primaryText == "The AI landscape in 2025 has seen remarkable progress.")
        #expect(assistant.toolInvocations.count == 1)
        #expect(assistant.toolInvocations[0].toolName == "web_search")

        // Sources: 1 single + 2 from batch = 3 total
        #expect(assistant.sources.count == 3)

        // Generic data parts: plan + steps (usage and suggested-questions have their own helpers)
        let dataNames = assistant.dataParts.map(\.name)
        #expect(dataNames.contains("plan"))
        #expect(dataNames.contains("steps"))

        // Suggested questions via helper
        let questions = assistant.suggestedQuestions
        #expect(questions?.count == 2)
        #expect(questions?[0] == "How does GPT-5 compare to Gemini 2.0?")

        // Usage via helper
        #expect(assistant.usageTokens?.totalTokens == 339)

        #expect(session.status == .ready)
    }

    // MARK: - Error mid-stream preserves partial state

    @Test func sessionHandlesErrorMidStreamAndPreservesPartialText() async throws {
        struct StreamCut: Error {}
        let transport = MockChatTransport(
            chunks: [
                .start(messageId: "msg-err"),
                .startStep,
                .textStart(id: "t1"),
                .textDelta(id: "t1", delta: "partial response"),
                .error(text: "stream error: connection reset"),
            ],
            error: StreamCut()
        )
        let session = ChatSession(id: "sess-err", transport: transport)
        await session.send(.user(text: "Query"))

        #expect(session.status == .error)
        #expect(session.error != nil)
    }

    // MARK: - Server-assigned message ID via start chunk

    @Test func sessionRenamesAssistantPlaceholderToServerAssignedId() async throws {
        let serverMsgId = "server-assigned-uuid-123"
        let transport = MockChatTransport(chunks: [
            .start(messageId: serverMsgId),
            .startStep,
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "Hello"),
            .textEnd(id: "t1"),
            .finishStep,
            .finish,
        ])
        let session = ChatSession(id: "sess-id", transport: transport)
        await session.send(.user(text: "Hi"))

        let assistant = session.messages.last!
        #expect(assistant.id == serverMsgId)
    }

    // MARK: - onDataPart fires for all data-* chunks

    @Test func onDataPartCallbackReceivesAllDataChunks() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-callbacks"),
            .startStep,
            .data(name: "plan", payload: .object(["content": .string("step 1")])),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "answer"),
            .textEnd(id: "t1"),
            .finishStep,
            .data(name: "usage", payload: .object([
                "promptTokens": .int(10),
                "completionTokens": .int(5),
                "totalTokens": .int(15),
            ])),
            .data(name: "suggested-questions", payload: .object([
                "questions": .array([.string("Q1")]),
            ])),
            .finish,
        ])
        let session = ChatSession(id: "sess-data-cb", transport: transport)

        var receivedNames: [String] = []
        session.onDataPart = { name, _ in receivedNames.append(name) }

        await session.send(.user(text: "go"))

        // plan + usage + suggested-questions
        #expect(receivedNames.count == 3)
        #expect(receivedNames.contains("plan"))
        #expect(receivedNames.contains("usage"))
        #expect(receivedNames.contains("suggested-questions"))
    }
}
