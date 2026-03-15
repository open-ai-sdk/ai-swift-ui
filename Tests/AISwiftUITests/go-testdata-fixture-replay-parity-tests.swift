import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Fixture replay parity tests
//
// Each test replays a .jsonl fixture from ai-go/uistream/testdata/ through the
// Swift decoder + reducer and asserts the assembled UIMessage matches Go's expectations.
// Fixture files in Tests/Fixtures/ are kept byte-for-byte identical to the Go originals.

private func loadAndDecodeFixture(_ name: String) throws -> [UIMessageChunk] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl") else {
        throw FixtureLoadError.notFound(name)
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    let decoder = UIMessageChunkDecoder()
    return try content
        .components(separatedBy: "\n")
        .compactMap { line -> UIMessageChunk? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return try decoder.decode(trimmed)
        }
}

private enum FixtureLoadError: Error {
    case notFound(String)
}

// MARK: - Parity test suite

struct GoTestdataFixtureReplayParityTests {

    // MARK: text-only.jsonl

    @Test func replayTextOnlyFixture() throws {
        let chunks = try loadAndDecodeFixture("text-only")
        var reducer = UIMessageStreamReducer(messageId: "msg-text-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)
        #expect(reducer.message.id == "msg-text-001")
        #expect(reducer.message.primaryText == "Hello! How can I help you today?")
        #expect(reducer.message.parts.count == 1)
        guard case .text(let tp) = reducer.message.parts[0] else {
            Issue.record("Expected text part"); return
        }
        #expect(tp.text == "Hello! How can I help you today?")
    }

    // MARK: tool-call-lifecycle.jsonl

    @Test func replayToolCallLifecycleFixture() throws {
        let chunks = try loadAndDecodeFixture("tool-call-lifecycle")
        var reducer = UIMessageStreamReducer(messageId: "msg-tool-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)
        #expect(reducer.message.id == "msg-tool-001")

        // Tool invocation
        let tools = reducer.message.toolInvocations
        #expect(tools.count == 1)
        #expect(tools[0].toolCallId == "tc-abc")
        #expect(tools[0].toolName == "search_documents")
        #expect(tools[0].state == .outputAvailable)
        if case .object(let inputObj) = tools[0].input {
            #expect(inputObj["query"]?.stringValue == "Go concurrency patterns")
        } else {
            Issue.record("Expected object input")
        }

        // Text content
        #expect(reducer.message.primaryText == "Based on the documents found, Go concurrency uses goroutines and channels.")

        // data-document-references promoted to sourceDocument parts
        let docRefs = reducer.message.documentReferences
        #expect(docRefs.count == 2)
        #expect(docRefs[0].id == "doc-1")
        #expect(docRefs[0].title == "Concurrency in Go")
        #expect(docRefs[1].id == "doc-2")
        #expect(docRefs[1].title == "Go Patterns")

        // data-usage accessible via helper
        let usage = reducer.message.usageTokens
        #expect(usage?.promptTokens == 120)
        #expect(usage?.completionTokens == 45)
        #expect(usage?.totalTokens == 165)

        // usage lands as DataPart (not promoted to sourceDocument)
        let dataNames = reducer.message.dataParts.map(\.name)
        #expect(dataNames.contains("usage"))
        #expect(!dataNames.contains("document-references"))
    }

    // MARK: reasoning-with-sources.jsonl

    @Test func replayReasoningWithSourcesFixture() throws {
        let chunks = try loadAndDecodeFixture("reasoning-with-sources")
        var reducer = UIMessageStreamReducer(messageId: "msg-reason-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)
        #expect(reducer.message.id == "msg-reason-001")

        // Parts: reasoning + text
        let parts = reducer.message.parts
        guard parts.count >= 2 else {
            Issue.record("Expected at least 2 parts, got \(parts.count)"); return
        }
        guard case .reasoning(let rp) = parts[0] else {
            Issue.record("Expected reasoning at index 0"); return
        }
        #expect(rp.reasoning.contains("think"))
        guard case .text(let tp) = parts[1] else {
            Issue.record("Expected text at index 1"); return
        }
        #expect(tp.text.contains("2025"))

        // Sources: `source` chunk + `sources` batch → 3 total (1 single + 2 in batch)
        let sources = reducer.message.sources
        #expect(sources.count == 3)
        let urls = sources.compactMap { p -> String? in
            if case .sourceURL(let s) = p { return s.url }
            return nil
        }
        #expect(urls.contains("https://example.com/ai-trends-2025"))
        #expect(urls.contains("https://example.com/llm-survey"))
    }

    // MARK: error-mid-stream.jsonl

    @Test func replayErrorMidStreamFixture() throws {
        let chunks = try loadAndDecodeFixture("error-mid-stream")
        var reducer = UIMessageStreamReducer(messageId: "msg-error-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished == false)
        #expect(reducer.error != nil)
        // Partial text accumulated before the error chunk
        #expect(reducer.message.primaryText.isEmpty == false)
    }

    // MARK: deep-thinking.jsonl (Swift fixture — same shape as Go deep-thinking-full.jsonl)

    @Test func replayDeepThinkingFixture() throws {
        let chunks = try loadAndDecodeFixture("deep-thinking")
        var reducer = UIMessageStreamReducer(messageId: "msg-deep-1")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)

        // Text content present
        #expect(reducer.message.primaryText.isEmpty == false)

        // Tool call present
        #expect(reducer.message.toolInvocations.count == 1)
        #expect(reducer.message.toolInvocations[0].toolName == "web_search")

        // Sources present (from `sources` batch chunk)
        #expect(reducer.message.sources.count >= 2)

        // data parts: plan + steps + (usage and suggested-questions via helpers or dataParts)
        let dataNames = reducer.message.dataParts.map(\.name)
        #expect(dataNames.contains("plan"))
        #expect(dataNames.contains("steps"))

        // suggested-questions helper
        let questions = reducer.message.suggestedQuestions
        #expect(questions != nil)
        #expect((questions?.count ?? 0) > 0)
    }

    // MARK: - Decoder-level fixture parity: chunk count matches expected

    @Test func textOnlyFixtureProducesExpectedChunkCount() throws {
        let chunks = try loadAndDecodeFixture("text-only")
        // start, start-step, text-start, text-delta x2, text-end, finish-step, finish = 8
        #expect(chunks.count == 8)
    }

    @Test func toolCallLifecycleFixtureDecodesWithoutError() throws {
        // Should not throw — validates full decoder coverage of the lifecycle fixture
        let chunks = try loadAndDecodeFixture("tool-call-lifecycle")
        #expect(chunks.isEmpty == false)
    }

    @Test func reasoningWithSourcesFixtureDecodesWithoutError() throws {
        let chunks = try loadAndDecodeFixture("reasoning-with-sources")
        #expect(chunks.isEmpty == false)
    }
}
