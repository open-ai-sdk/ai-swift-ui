import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Gemini grounding metadata fixture + typed accessor tests
//
// Covers:
//  1. Decode grounding metadata from a finish chunk stream
//  2. Typed accessor googleGroundingMetadata on UIMessage
//  3. groundingSearchQueries accessor
//  4. groundingSources accessor
//  5. Nil handling when google key absent
//  6. Codable round-trip for GoogleGroundingMetadata
//  7. Full stream fixture replay through decoder + reducer

struct GeminiGroundingFixtureTests {

    // MARK: 1 - Finish chunk with message-metadata attaches to UIMessage

    @Test func decodeGroundingMetadataFromFinishChunkStream() throws {
        let line = """
            data: {"type":"message-metadata","messageMetadata":\
            {"google":{"groundingMetadata":{"webSearchQueries":["test query"]}}}}
            """
        let decoder = UIMessageChunkDecoder()
        let chunk = try decoder.decode(line)
        guard case .messageMetadata(let meta) = chunk else {
            Issue.record("Expected messageMetadata chunk"); return
        }
        guard case .object(let google) = meta["google"],
              case .object(let gm) = google["groundingMetadata"],
              case .array(let queries) = gm["webSearchQueries"] else {
            Issue.record("Unexpected metadata shape"); return
        }
        #expect(queries.first?.stringValue == "test query")

        var reducer = UIMessageStreamReducer(messageId: "msg-1")
        reducer.apply(.messageMetadata(metadata: meta))
        #expect(reducer.message.metadata != nil)
        #expect(reducer.message.metadata?["google"] != nil)
    }

    // MARK: 2 - Typed accessor googleGroundingMetadata

    @Test func typedAccessorReturnsGoogleGroundingMetadata() throws {
        let msg = makeMessageWithGrounding()
        let grounding = msg.googleGroundingMetadata
        #expect(grounding != nil)
        #expect(grounding?.webSearchQueries?.first == "Swift programming language")
        #expect(grounding?.groundingChunks?.count == 2)
        #expect(grounding?.groundingSupports?.count == 1)
        #expect(grounding?.searchEntryPoint?.renderedContent == "<html>search</html>")
    }

    // MARK: 3 - groundingSearchQueries accessor

    @Test func groundingSearchQueriesAccessorReturnsValues() {
        let msg = makeMessageWithGrounding()
        let queries = msg.groundingSearchQueries
        #expect(queries != nil)
        #expect(queries?.count == 2)
        #expect(queries?.contains("Swift programming language") == true)
        #expect(queries?.contains("Swift open source") == true)
    }

    // MARK: 4 - groundingSources accessor

    @Test func groundingSourcesAccessorReturnsURLAndTitle() {
        let msg = makeMessageWithGrounding()
        let sources = msg.groundingSources
        #expect(sources != nil)
        #expect(sources?.count == 2)
        #expect(sources?[0].url == "https://swift.org")
        #expect(sources?[0].title == "Swift.org")
        #expect(sources?[1].url == "https://developer.apple.com/swift/")
        #expect(sources?[1].title == "Apple Swift")
    }

    // MARK: 5 - Nil handling when google key absent

    @Test func nilHandlingWhenGoogleKeyAbsent() {
        var msg = UIMessage(id: "msg-nil", role: .assistant)
        #expect(msg.googleGroundingMetadata == nil)
        #expect(msg.groundingSearchQueries == nil)
        #expect(msg.groundingSources == nil)

        // With metadata but no google key
        msg.metadata = ["other": .string("value")]
        #expect(msg.googleGroundingMetadata == nil)

        // With google key but no groundingMetadata
        msg.metadata = ["google": .object(["otherField": .string("x")])]
        #expect(msg.googleGroundingMetadata == nil)
    }

    // MARK: 6 - Codable round-trip

    @Test func codableRoundTripGoogleGroundingMetadata() throws {
        let original = GoogleGroundingMetadata(
            groundingChunks: [
                GroundingChunk(web: WebChunk(uri: "https://example.com", title: "Example")),
                GroundingChunk(web: WebChunk(uri: "https://other.com", title: nil))
            ],
            groundingSupports: [
                GroundingSupport(
                    segment: GroundingSegment(startIndex: 0, endIndex: 50, text: "Sample text"),
                    groundingChunkIndices: [0, 1],
                    confidenceScores: [0.95, 0.87]
                )
            ],
            webSearchQueries: ["query one", "query two"],
            searchEntryPoint: SearchEntryPoint(renderedContent: "<html>results</html>")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GoogleGroundingMetadata.self, from: data)

        #expect(decoded == original)
        #expect(decoded.groundingChunks?.count == 2)
        #expect(decoded.groundingChunks?[0].web?.uri == "https://example.com")
        #expect(decoded.groundingChunks?[1].web?.title == nil)
        #expect(decoded.groundingSupports?[0].confidenceScores == [0.95, 0.87])
        #expect(decoded.webSearchQueries == ["query one", "query two"])
        #expect(decoded.searchEntryPoint?.renderedContent == "<html>results</html>")
    }

    // MARK: 7 - Full stream fixture replay

    @Test func fullStreamFixtureReplayGeminiGroundedResponse() throws {
        let chunks = try loadAndDecodeGroundingFixture("gemini-grounded-response")
        var reducer = UIMessageStreamReducer(messageId: "msg-gemini-grounded-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.finishReason == "stop")
        #expect(reducer.error == nil)

        // Text content
        let text = reducer.message.primaryText
        #expect(text.contains("Swift was introduced by Apple in 2014"))
        #expect(text.contains("open source"))

        // Metadata attached
        #expect(reducer.message.metadata != nil)

        // Typed grounding metadata
        let grounding = reducer.message.googleGroundingMetadata
        #expect(grounding != nil)
        #expect(grounding?.webSearchQueries?.contains("Swift programming language history") == true)
        #expect(grounding?.webSearchQueries?.contains("Swift open source") == true)

        // Sources
        let sources = reducer.message.groundingSources
        #expect(sources?.count == 2)
        #expect(sources?[0].url == "https://swift.org")
        #expect(sources?[0].title == "Swift.org")
        #expect(sources?[1].url == "https://developer.apple.com/swift/")

        // Supports
        #expect(grounding?.groundingSupports?.count == 2)
        #expect(grounding?.groundingSupports?[0].confidenceScores?[0] == 0.95)

        // Search entry point
        #expect(grounding?.searchEntryPoint?.renderedContent != nil)
    }
}

// MARK: - Helpers

private func loadAndDecodeGroundingFixture(_ name: String) throws -> [UIMessageChunk] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl") else {
        throw FixtureError.notFound(name)
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

private enum FixtureError: Error {
    case notFound(String)
}

private func makeMessageWithGrounding() -> UIMessage {
    // Build a UIMessage with typed grounding metadata embedded in .metadata
    let groundingJSON: [String: JSONValue] = [
        "google": .object([
            "groundingMetadata": .object([
                "groundingChunks": .array([
                    .object(["web": .object(["uri": .string("https://swift.org"), "title": .string("Swift.org")])]),
                    .object(["web": .object(["uri": .string("https://developer.apple.com/swift/"), "title": .string("Apple Swift")])])
                ]),
                "groundingSupports": .array([
                    .object([
                        "segment": .object([
                            "startIndex": .int(0),
                            "endIndex": .int(50),
                            "text": .string("Swift was introduced by Apple in 2014.")
                        ]),
                        "groundingChunkIndices": .array([.int(0)]),
                        "confidenceScores": .array([.double(0.95)])
                    ])
                ]),
                "webSearchQueries": .array([
                    .string("Swift programming language"),
                    .string("Swift open source")
                ]),
                "searchEntryPoint": .object([
                    "renderedContent": .string("<html>search</html>")
                ])
            ])
        ])
    ]
    return UIMessage(id: "msg-test", role: .assistant, metadata: groundingJSON)
}
