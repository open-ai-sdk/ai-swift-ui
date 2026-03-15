import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Source chunk decoding and UIMessage source part accumulation tests

struct SourceChunkDecodingAndReducerTests {

    let decoder = UIMessageChunkDecoder()

    // MARK: - Single source chunk

    @Test func decodesSingleSourceChunkWithAllFields() throws {
        let json = #"data: {"type":"source","id":"src-1","url":"https://example.com","title":"Example Site"}"#
        let chunk = try decoder.decode(json)
        guard case .source(let id, let url, let title) = chunk else {
            Issue.record("Expected .source chunk"); return
        }
        #expect(id == "src-1")
        #expect(url == "https://example.com")
        #expect(title == "Example Site")
    }

    @Test func decodesSingleSourceChunkWithNilOptionals() throws {
        let json = #"data: {"type":"source","url":"https://example.com"}"#
        let chunk = try decoder.decode(json)
        guard case .source(let id, let url, let title) = chunk else {
            Issue.record("Expected .source chunk"); return
        }
        #expect(id == nil)
        #expect(url == "https://example.com")
        #expect(title == nil)
    }

    @Test func reducerAppendsSourceURLPartFromSourceChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-src")
        reducer.apply(.start(messageId: "msg-src"))
        reducer.apply(.source(id: "s1", url: "https://go.dev", title: "Go Dev"))

        let sources = reducer.message.sources
        #expect(sources.count == 1)
        if case .sourceURL(let p) = sources[0] {
            #expect(p.id == "s1")
            #expect(p.url == "https://go.dev")
            #expect(p.title == "Go Dev")
        } else {
            Issue.record("Expected .sourceURL part")
        }
    }

    // MARK: - Batch sources chunk

    @Test func decodesBatchSourcesChunk() throws {
        let payload = #"{"type":"sources","sources":"#
            + #"[{"id":"s1","url":"https://a.com","title":"A"},"#
            + #"{"id":"s2","url":"https://b.com","title":"B"}]}"#
        let json = "data: " + payload
        let chunk = try decoder.decode(json)
        guard case .sources(let list) = chunk else {
            Issue.record("Expected .sources chunk"); return
        }
        #expect(list.count == 2)
        #expect(list[0].id == "s1")
        #expect(list[0].url == "https://a.com")
        #expect(list[0].title == "A")
        #expect(list[1].id == "s2")
        #expect(list[1].url == "https://b.com")
    }

    @Test func reducerAppendsAllSourceURLPartsFromBatchSourcesChunk() {
        let sourceParts = [
            SourceURLPart(id: "s1", url: "https://one.com", title: "One"),
            SourceURLPart(id: "s2", url: "https://two.com", title: "Two"),
            SourceURLPart(id: "s3", url: "https://three.com", title: nil),
        ]
        var reducer = UIMessageStreamReducer(messageId: "msg-sources")
        reducer.apply(.start(messageId: "msg-sources"))
        reducer.apply(.sources(sourceParts))

        let sources = reducer.message.sources
        #expect(sources.count == 3)
        if case .sourceURL(let p) = sources[2] {
            #expect(p.url == "https://three.com")
            #expect(p.title == nil)
        } else {
            Issue.record("Expected .sourceURL at index 2")
        }
    }

    @Test func reducerAccumulatesSourcesFromBothSingleAndBatchChunks() {
        var reducer = UIMessageStreamReducer(messageId: "msg-mixed-src")
        reducer.apply(.start(messageId: "msg-mixed-src"))
        reducer.apply(.startStep)
        reducer.apply(.textStart(id: "t1"))
        reducer.apply(.textDelta(id: "t1", delta: "answer"))
        reducer.apply(.textEnd(id: "t1"))
        reducer.apply(.finishStep)
        reducer.apply(.source(id: "s1", url: "https://a.com", title: "A"))
        reducer.apply(.sources([
            SourceURLPart(id: "s2", url: "https://b.com", title: "B"),
            SourceURLPart(id: "s3", url: "https://c.com", title: "C"),
        ]))
        reducer.apply(.finish)

        #expect(reducer.message.sources.count == 3)
        #expect(reducer.isFinished)
    }

    @Test func decodesEmptySourcesArray() throws {
        let json = #"data: {"type":"sources","sources":[]}"#
        let chunk = try decoder.decode(json)
        guard case .sources(let list) = chunk else {
            Issue.record("Expected .sources chunk"); return
        }
        #expect(list.isEmpty)
    }

    // MARK: - SourceURLPart Codable round-trip

    @Test func sourceURLPartCodableRoundTrip() throws {
        let part = SourceURLPart(id: "src-rt", url: "https://roundtrip.com", title: "Round Trip")
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(SourceURLPart.self, from: data)
        #expect(decoded == part)
    }

    @Test func sourceURLPartCodableRoundTripWithNilFields() throws {
        let part = SourceURLPart(id: nil, url: "https://minimal.com", title: nil)
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(SourceURLPart.self, from: data)
        #expect(decoded == part)
    }

    // MARK: - SourceDocumentPart (document-references)

    @Test func reducerEmitsSourceDocumentPartsFromDocumentReferencesChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-doc-src")
        reducer.apply(.start(messageId: "msg-doc-src"))
        reducer.apply(.data(name: "document-references", payload: .array([
            .object(["id": .string("doc-1"), "title": .string("Go Spec")]),
            .object(["id": .string("doc-2"), "title": .string("Effective Go")]),
        ])))
        reducer.apply(.finish)

        let docRefs = reducer.message.documentReferences
        #expect(docRefs.count == 2)
        #expect(docRefs[0].id == "doc-1")
        #expect(docRefs[0].title == "Go Spec")
        #expect(docRefs[1].id == "doc-2")
        #expect(docRefs[1].title == "Effective Go")
    }

    @Test func sourceURLAndSourceDocumentAreDistinguishableViaHelpers() {
        var reducer = UIMessageStreamReducer(messageId: "msg-separation")
        reducer.apply(.start(messageId: "msg-separation"))
        reducer.apply(.source(id: "url-1", url: "https://web.com", title: "Web"))
        reducer.apply(.data(name: "document-references", payload: .array([
            .object(["id": .string("doc-1"), "title": .string("Internal Doc")]),
        ])))
        reducer.apply(.finish)

        // sources() returns all source-type parts (sourceURL + sourceDocument)
        #expect(reducer.message.sources.count == 2)
        // documentReferences helper returns only sourceDocument parts
        #expect(reducer.message.documentReferences.count == 1)
        #expect(reducer.message.documentReferences[0].id == "doc-1")
        // Only 1 is a web URL
        let urlParts = reducer.message.sources.filter { if case .sourceURL = $0 { return true }; return false }
        #expect(urlParts.count == 1)
    }

    // MARK: - Fixture replay: reasoning-with-sources

    @Test func fixtureReplayReasoningWithSourcesProducesCorrectParts() throws {
        guard let url = Bundle.module.url(forResource: "Fixtures/reasoning-with-sources", withExtension: "jsonl") else {
            Issue.record("reasoning-with-sources.jsonl fixture not found"); return
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = UIMessageChunkDecoder()
        let chunks = try content.components(separatedBy: "\n").compactMap { line -> UIMessageChunk? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return try decoder.decode(trimmed)
        }

        var reducer = UIMessageStreamReducer(messageId: "msg-reason-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.error == nil)
        // reasoning part + text part
        let parts = reducer.message.parts
        #expect(parts.count >= 2)

        let hasReasoning = parts.contains { if case .reasoning = $0 { return true }; return false }
        #expect(hasReasoning)

        // Both `source` and `sources` chunks arrive — sources accumulate
        #expect(reducer.message.sources.count >= 2)

        let urls = reducer.message.sources.compactMap { part -> String? in
            if case .sourceURL(let p) = part { return p.url }
            return nil
        }
        #expect(urls.contains("https://example.com/ai-trends-2025"))
    }
}
