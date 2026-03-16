import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Helpers

private func loadFixture(_ name: String) throws -> [UIMessageChunk] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
        throw FixtureError.notFound(name)
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    let decoder = UIMessageChunkDecoder()
    return try content
        .components(separatedBy: "\n")
        .compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return try decoder.decode(trimmed)
        }
}

private enum FixtureError: Error {
    case notFound(String)
}

// MARK: - UIMessageChunkDecoder unit tests

struct StreamChunkDecoderTests {

    let decoder = UIMessageChunkDecoder()

    @Test func decodesStartChunk() throws {
        let chunk = try decoder.decode(#"data: {"type":"start","messageId":"msg-001"}"#)
        guard case .start(let msgId) = chunk else { Issue.record("Expected start"); return }
        #expect(msgId == "msg-001")
    }

    @Test func decodesTextDelta() throws {
        let chunk = try decoder.decode(#"data: {"type":"text-delta","id":"text_1","delta":"Hello"}"#)
        guard case .textDelta(let id, let delta) = chunk else { Issue.record("Expected textDelta"); return }
        #expect(id == "text_1")
        #expect(delta == "Hello")
    }

    @Test func decodesReasoningDelta() throws {
        let chunk = try decoder.decode(#"data: {"type":"reasoning-delta","id":"text_1","delta":"thinking"}"#)
        guard case .reasoningDelta(let id, let delta) = chunk else { Issue.record("Expected reasoningDelta"); return }
        #expect(id == "text_1")
        #expect(delta == "thinking")
    }

    @Test func decodesToolInputAvailable() throws {
        let json = #"data: {"type":"tool-input-available","toolCallId":"tc1","toolName":"search","input":{"q":"go"}}"#
        let chunk = try decoder.decode(json)
        guard case .toolInputAvailable(let tcId, let name, let input) = chunk else {
            Issue.record("Expected toolInputAvailable"); return
        }
        #expect(tcId == "tc1")
        #expect(name == "search")
        if case .object(let obj) = input, case .string(let q) = obj["q"] {
            #expect(q == "go")
        } else {
            Issue.record("Unexpected input shape")
        }
    }

    @Test func decodesToolOutputAvailable() throws {
        let json = #"data: {"type":"tool-output-available","toolCallId":"tc1","output":{"results":[]}}"#
        let chunk = try decoder.decode(json)
        guard case .toolOutputAvailable(let tcId, _) = chunk else {
            Issue.record("Expected toolOutputAvailable"); return
        }
        #expect(tcId == "tc1")
    }

    @Test func decodesSourceChunk() throws {
        let json = #"data: {"type":"source","id":"src-1","url":"https://example.com","title":"Example"}"#
        let chunk = try decoder.decode(json)
        guard case .source(let id, let url, let title) = chunk else { Issue.record("Expected source"); return }
        #expect(id == "src-1")
        #expect(url == "https://example.com")
        #expect(title == "Example")
    }

    @Test func decodesSourcesChunk() throws {
        let json = #"data: {"type":"sources","sources":[{"url":"https://a.com","title":"A"},{"url":"https://b.com","title":"B"}]}"#
        let chunk = try decoder.decode(json)
        guard case .sources(let list) = chunk else { Issue.record("Expected sources"); return }
        #expect(list.count == 2)
        #expect(list[0].url == "https://a.com")
    }

    @Test func decodesDataChunk() throws {
        let json = #"data: {"type":"data-plan","data":{"content":"step 1"}}"#
        let chunk = try decoder.decode(json)
        guard case .data(let name, let payload, _, _) = chunk else { Issue.record("Expected data"); return }
        #expect(name == "plan")
        if case .object(let obj) = payload, case .string(let content) = obj["content"] {
            #expect(content == "step 1")
        } else {
            Issue.record("Unexpected data payload")
        }
    }

    @Test func decodesDoneReturnsNil() throws {
        let result = try decoder.decode("data: [DONE]")
        #expect(result == nil)
    }

    @Test func ignoresNonDataLines() throws {
        let result = try decoder.decode("event: message")
        #expect(result == nil)
    }

    @Test func decodesErrorChunk() throws {
        let json = #"data: {"type":"error","errorText":"connection reset"}"#
        let chunk = try decoder.decode(json)
        guard case .error(let text) = chunk else { Issue.record("Expected error"); return }
        #expect(text == "connection reset")
    }

    // MARK: - Golden fixture tests

    @Test func goldenTextOnly() throws {
        let chunks = try loadFixture("text-only.jsonl")
        var reducer = UIMessageStreamReducer(messageId: "msg-text-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)
        #expect(reducer.message.primaryText == "Hello! How can I help you today?")
        #expect(reducer.message.parts.count == 1)
        if case .text(let p) = reducer.message.parts[0] {
            #expect(p.text == "Hello! How can I help you today?")
        } else {
            Issue.record("Expected text part")
        }
    }

    @Test func goldenReasoningAndText() throws {
        let chunks = try loadFixture("reasoning-and-text.jsonl")
        var reducer = UIMessageStreamReducer(messageId: "msg-reasoning-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)

        let parts = reducer.message.parts
        // Should have reasoning part then text part
        #expect(parts.count == 2)
        if case .reasoning(let r) = parts[0] {
            #expect(r.reasoning.contains("think"))
        } else {
            Issue.record("Expected reasoning part at index 0")
        }
        if case .text(let t) = parts[1] {
            #expect(t.text == "Here is my answer.")
        } else {
            Issue.record("Expected text part at index 1")
        }
    }

    @Test func goldenToolCall() throws {
        let chunks = try loadFixture("tool-call.jsonl")
        var reducer = UIMessageStreamReducer(messageId: "msg-tool-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)

        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].toolCallId == "tc1")
        #expect(invocations[0].toolName == "search")
        #expect(invocations[0].state == .outputAvailable)

        #expect(reducer.message.primaryText == "Found nothing.")
    }

    @Test func goldenErrorMidStream() throws {
        let chunks = try loadFixture("error-mid-stream.jsonl")
        var reducer = UIMessageStreamReducer(messageId: "msg-error-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished == false)
        #expect(reducer.error != nil)
        #expect(reducer.error?.contains("connection reset") == true)
        // partial text should still be preserved
        #expect(reducer.message.primaryText == "partial response")
    }

    @Test func goldenDeepThinking() throws {
        let chunks = try loadFixture("deep-thinking.jsonl")
        var reducer = UIMessageStreamReducer(messageId: "msg-deep-1")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)

        let parts = reducer.message.parts
        // data-plan, data-steps, reasoning, tool-invocation, text, 2 sourceURLs, data-artifacts, data-suggested-questions
        #expect(parts.count >= 7)

        #expect(reducer.message.primaryText.contains("AI in 2025"))
        #expect(reducer.message.toolInvocations.count == 1)
        #expect(reducer.message.toolInvocations[0].toolName == "web_search")
        #expect(reducer.message.sources.count == 2)

        let dataParts = reducer.message.dataParts
        let dataNames = dataParts.map(\.name)
        #expect(dataNames.contains("plan"))
        #expect(dataNames.contains("steps"))
        #expect(dataNames.contains("artifacts"))
        #expect(dataNames.contains("suggested-questions"))
    }
}
