import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Helpers

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
}

// MARK: - UIMessagePart round-trip tests

struct ModelCodableTests {

    @Test func textPartRoundTrip() throws {
        let part = UIMessagePart.text(TextPart(text: "Hello world"))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func reasoningPartRoundTrip() throws {
        let part = UIMessagePart.reasoning(ReasoningPart(reasoning: "thinking...", signature: "sig-abc"))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func reasoningPartNoSignatureRoundTrip() throws {
        let part = UIMessagePart.reasoning(ReasoningPart(reasoning: "plain reasoning"))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func toolInvocationPartInputStreamingRoundTrip() throws {
        let part = UIMessagePart.toolInvocation(ToolInvocationPart(
            toolCallId: "tc1",
            toolName: "search",
            state: .inputStreaming,
            input: .object(["q": .string("go")])
        ))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func toolInvocationPartOutputAvailableRoundTrip() throws {
        let part = UIMessagePart.toolInvocation(ToolInvocationPart(
            toolCallId: "tc2",
            toolName: "calculator",
            state: .outputAvailable,
            input: .object(["expr": .string("2+2")]),
            output: .int(4)
        ))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func toolInvocationPartOutputErrorRoundTrip() throws {
        let part = UIMessagePart.toolInvocation(ToolInvocationPart(
            toolCallId: "tc3",
            toolName: "fetch",
            state: .outputError,
            input: .object(["url": .string("https://example.com")]),
            output: .object(["error": .string("timeout")])
        ))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func sourceURLPartRoundTrip() throws {
        let part = UIMessagePart.sourceURL(SourceURLPart(id: "src-1", url: "https://example.com", title: "Example"))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func sourceDocumentPartRoundTrip() throws {
        let part = UIMessagePart.sourceDocument(SourceDocumentPart(
            id: "doc-1",
            title: "AI Report",
            mediaType: "application/pdf",
            url: "https://storage.example.com/report.pdf",
            content: "AI trends in 2025..."
        ))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func filePartRoundTrip() throws {
        let part = UIMessagePart.file(FilePart(url: "https://storage.example.com/image.png", mediaType: "image/png", name: "image.png"))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    @Test func dataPartRoundTrip() throws {
        let part = UIMessagePart.data(DataPart(
            name: "plan",
            data: .object(["content": .string("Research AI trends")])
        ))
        let decoded = try roundTrip(part)
        #expect(decoded == part)
    }

    // MARK: - UIMessage round-trip

    @Test func uiMessageRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let msg = UIMessage(
            id: "msg-001",
            role: .assistant,
            parts: [
                .text(TextPart(text: "Hello")),
                .reasoning(ReasoningPart(reasoning: "I thought...")),
            ],
            createdAt: date
        )
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    // MARK: - Computed properties

    @Test func primaryTextConcatenation() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "Hello ")),
            .reasoning(ReasoningPart(reasoning: "thought")),
            .text(TextPart(text: "world")),
        ])
        #expect(msg.primaryText == "Hello world")
    }

    @Test func toolInvocationsFilter() {
        let tool = ToolInvocationPart(toolCallId: "tc1", toolName: "search", state: .outputAvailable, input: .null)
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "answer")),
            .toolInvocation(tool),
        ])
        #expect(msg.toolInvocations.count == 1)
        #expect(msg.toolInvocations[0].toolCallId == "tc1")
    }

    @Test func sourcesFilter() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "answer")),
            .sourceURL(SourceURLPart(url: "https://a.com")),
            .sourceDocument(SourceDocumentPart(title: "Doc")),
        ])
        #expect(msg.sources.count == 2)
    }

    // MARK: - JSONValue tests

    @Test func jsonValueRoundTrip() throws {
        let value = JSONValue.object([
            "name": .string("test"),
            "count": .int(42),
            "ratio": .double(3.14),
            "active": .bool(true),
            "tags": .array([.string("a"), .string("b")]),
            "nested": .object(["x": .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    // MARK: - NewUIMessage

    @Test func newUIMessageMakesMessage() {
        let newMsg = NewUIMessage.user(text: "Hi there")
        let msg = newMsg.makeMessage(id: "msg-001")
        #expect(msg.role == .user)
        #expect(msg.primaryText == "Hi there")
        #expect(msg.parts.count == 1)
    }

    @Test func newUIMessageWithFiles() {
        let file = FilePart(url: "data:image/png;base64,abc", mediaType: "image/png", name: "photo.png")
        let newMsg = NewUIMessage.user(text: "See this image", files: [file])
        let msg = newMsg.makeMessage(id: "msg-002")
        #expect(msg.parts.count == 2)
        if case .file(let fp) = msg.parts[1] {
            #expect(fp.name == "photo.png")
        } else {
            Issue.record("Expected file part")
        }
    }
}
