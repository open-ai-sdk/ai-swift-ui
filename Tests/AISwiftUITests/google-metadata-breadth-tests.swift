import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Google metadata breadth tests (ai-4l9)
//
// Covers:
//  1. Mixed grounding chunks (web + retrievedContext + image + maps) → allGroundingSources
//  2. Safety ratings: googleSafetyRatings decodes correctly
//  3. URL context metadata: googleURLContextMetadata decodes correctly
//  4. Codable round-trip: GroundingChunk with all new source types
//  5. Codable round-trip: GoogleSafetyRating
//  6. Full stream replay: JSONL fixture with mixed sources → UIMessage has all source types

struct GoogleMetadataBreadthTests {

    // MARK: 1 - Mixed grounding chunks → allGroundingSources

    @Test func allGroundingSourcesReturnsMixedTypes() {
        let msg = makeMixedSourcesMessage()
        let sources = msg.allGroundingSources
        #expect(sources != nil)
        #expect(sources?.count == 4)

        let types = sources?.map(\.type) ?? []
        #expect(types.contains("url"))
        #expect(types.contains("retrieved-context"))
        #expect(types.contains("image"))
        #expect(types.contains("maps"))

        let webSource = sources?.first { $0.type == "url" }
        #expect(webSource?.url == "https://swift.org")
        #expect(webSource?.title == "Swift.org")

        let rcSource = sources?.first { $0.type == "retrieved-context" }
        #expect(rcSource?.url == "https://docs.example.com/swift")
        #expect(rcSource?.title == "Swift Docs")

        let imgSource = sources?.first { $0.type == "image" }
        #expect(imgSource?.url == "https://images.example.com/swift-logo.png")
        #expect(imgSource?.title == "Swift Logo")

        let mapsSource = sources?.first { $0.type == "maps" }
        #expect(mapsSource?.url == "https://maps.example.com/apple-hq")
        #expect(mapsSource?.title == "Apple HQ")
    }

    @Test func allGroundingSourcesNilWhenNoChunks() {
        let msg = UIMessage(id: "msg-empty", role: .assistant)
        #expect(msg.allGroundingSources == nil)
    }

    @Test func allGroundingSourcesNilWhenChunksHaveNoURI() {
        let metadata: [String: JSONValue] = [
            "google": .object([
                "groundingMetadata": .object([
                    "groundingChunks": .array([
                        .object(["web": .object(["title": .string("No URI")])])
                    ])
                ])
            ])
        ]
        let msg = UIMessage(id: "msg-no-uri", role: .assistant, metadata: metadata)
        #expect(msg.allGroundingSources == nil)
    }

    // MARK: 2 - Safety ratings decode

    @Test func googleSafetyRatingsDecodes() {
        let msg = makeMixedSourcesMessage()
        let ratings = msg.googleSafetyRatings
        #expect(ratings != nil)
        #expect(ratings?.count == 2)
        #expect(ratings?[0].category == "HARM_CATEGORY_DANGEROUS_CONTENT")
        #expect(ratings?[0].probability == "NEGLIGIBLE")
        #expect(ratings?[0].blocked == false)
        #expect(ratings?[1].category == "HARM_CATEGORY_HATE_SPEECH")
    }

    @Test func googleSafetyRatingsNilWhenAbsent() {
        let msg = UIMessage(id: "msg-no-ratings", role: .assistant)
        #expect(msg.googleSafetyRatings == nil)

        // With google key but no safetyRatings
        let msg2 = UIMessage(
            id: "msg-no-ratings-2",
            role: .assistant,
            metadata: ["google": .object(["groundingMetadata": .object([:])])]
        )
        #expect(msg2.googleSafetyRatings == nil)
    }

    // MARK: 3 - URL context metadata decodes

    @Test func googleURLContextMetadataDecodes() {
        let msg = makeMixedSourcesMessage()
        let urlCtx = msg.googleURLContextMetadata
        #expect(urlCtx != nil)
        #expect(urlCtx?.urlMetadata?.count == 2)
        #expect(urlCtx?.urlMetadata?[0].url == "https://swift.org")
        #expect(urlCtx?.urlMetadata?[0].title == "Swift.org")
        #expect(urlCtx?.urlMetadata?[0].snippet == "Swift is a general-purpose programming language.")
        #expect(urlCtx?.urlMetadata?[1].url == "https://docs.example.com/swift")
    }

    @Test func googleURLContextMetadataNilWhenAbsent() {
        let msg = UIMessage(id: "msg-no-url-ctx", role: .assistant)
        #expect(msg.googleURLContextMetadata == nil)
    }

    // MARK: 4 - Codable round-trip: GroundingChunk with all source types

    @Test func groundingChunkWithAllSourceTypesRoundTrip() throws {
        let chunk = GroundingChunk(
            web: WebChunk(uri: "https://swift.org", title: "Swift.org"),
            retrievedContext: RetrievedContextChunk(uri: "https://docs.example.com", title: "Docs"),
            image: ImageChunk(uri: "https://images.example.com/logo.png", title: "Logo"),
            maps: MapsChunk(uri: "https://maps.example.com/hq", title: "HQ")
        )
        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(GroundingChunk.self, from: data)
        #expect(decoded == chunk)
        #expect(decoded.web?.uri == "https://swift.org")
        #expect(decoded.retrievedContext?.uri == "https://docs.example.com")
        #expect(decoded.retrievedContext?.title == "Docs")
        #expect(decoded.image?.uri == "https://images.example.com/logo.png")
        #expect(decoded.maps?.uri == "https://maps.example.com/hq")
        #expect(decoded.maps?.title == "HQ")
    }

    @Test func groundingChunkWebOnlyRoundTrip() throws {
        let chunk = GroundingChunk(web: WebChunk(uri: "https://swift.org", title: "Swift.org"))
        let decoded = try JSONDecoder().decode(GroundingChunk.self, from: try JSONEncoder().encode(chunk))
        #expect(decoded == chunk)
        #expect(decoded.retrievedContext == nil)
        #expect(decoded.image == nil)
        #expect(decoded.maps == nil)
    }

    @Test func groundingChunkRetrievedContextOnlyRoundTrip() throws {
        let chunk = GroundingChunk(retrievedContext: RetrievedContextChunk(uri: "https://docs.example.com", title: "Docs"))
        let decoded = try JSONDecoder().decode(GroundingChunk.self, from: try JSONEncoder().encode(chunk))
        #expect(decoded == chunk)
        #expect(decoded.web == nil)
        #expect(decoded.retrievedContext?.uri == "https://docs.example.com")
    }

    // MARK: 5 - Codable round-trip: GoogleSafetyRating

    @Test func googleSafetyRatingRoundTrip() throws {
        let rating = GoogleSafetyRating(
            category: "HARM_CATEGORY_DANGEROUS_CONTENT",
            probability: "LOW",
            blocked: true
        )
        let data = try JSONEncoder().encode(rating)
        let decoded = try JSONDecoder().decode(GoogleSafetyRating.self, from: data)
        #expect(decoded == rating)
        #expect(decoded.category == "HARM_CATEGORY_DANGEROUS_CONTENT")
        #expect(decoded.probability == "LOW")
        #expect(decoded.blocked == true)
    }

    @Test func googleSafetyRatingNilFieldsRoundTrip() throws {
        let rating = GoogleSafetyRating()
        let decoded = try JSONDecoder().decode(GoogleSafetyRating.self, from: try JSONEncoder().encode(rating))
        #expect(decoded == rating)
        #expect(decoded.category == nil)
        #expect(decoded.blocked == nil)
    }

    @Test func googleURLContextMetadataRoundTrip() throws {
        let meta = GoogleURLContextMetadata(urlMetadata: [
            URLMetadataEntry(url: "https://swift.org", title: "Swift.org", snippet: "Swift language"),
            URLMetadataEntry(url: "https://example.com", title: nil, snippet: nil)
        ])
        let decoded = try JSONDecoder().decode(GoogleURLContextMetadata.self, from: try JSONEncoder().encode(meta))
        #expect(decoded == meta)
        #expect(decoded.urlMetadata?.count == 2)
        #expect(decoded.urlMetadata?[0].snippet == "Swift language")
        #expect(decoded.urlMetadata?[1].title == nil)
    }

    // MARK: 6 - Full stream fixture replay with mixed sources

    @Test func fullStreamFixtureReplayMixedSources() throws {
        let chunks = try loadGroundingFixture("gemini-mixed-sources-response")
        var reducer = UIMessageStreamReducer(messageId: "msg-mixed-sources-001")
        reducer.applyAll(chunks)

        #expect(reducer.isFinished)
        #expect(reducer.finishReason == "stop")
        #expect(reducer.error == nil)
        #expect(reducer.message.primaryText == "Here are results from multiple source types.")

        // Grounding metadata present
        let grounding = reducer.message.googleGroundingMetadata
        #expect(grounding != nil)
        #expect(grounding?.groundingChunks?.count == 4)
        #expect(grounding?.webSearchQueries?.first == "Swift mixed sources")

        // allGroundingSources returns all 4 types
        let sources = reducer.message.allGroundingSources
        #expect(sources?.count == 4)
        let types = Set(sources?.map(\.type) ?? [])
        #expect(types == ["url", "retrieved-context", "image", "maps"])

        // Safety ratings decoded
        let ratings = reducer.message.googleSafetyRatings
        #expect(ratings?.count == 2)
        #expect(ratings?[0].category == "HARM_CATEGORY_DANGEROUS_CONTENT")
        #expect(ratings?[0].probability == "NEGLIGIBLE")
        #expect(ratings?[0].blocked == false)

        // URL context metadata decoded
        let urlCtx = reducer.message.googleURLContextMetadata
        #expect(urlCtx?.urlMetadata?.count == 2)
        #expect(urlCtx?.urlMetadata?[0].url == "https://swift.org")
        #expect(urlCtx?.urlMetadata?[0].snippet == "Swift is a general-purpose programming language.")

        // Legacy groundingSources still works (web-only)
        let legacySources = reducer.message.groundingSources
        #expect(legacySources?.count == 1)
        #expect(legacySources?[0].url == "https://swift.org")
    }
}

// MARK: - Helpers

private func loadGroundingFixture(_ name: String) throws -> [UIMessageChunk] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl") else {
        throw GroundingFixtureError.notFound(name)
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

private enum GroundingFixtureError: Error {
    case notFound(String)
}

private func makeMixedSourcesMessage() -> UIMessage {
    let metadata: [String: JSONValue] = [
        "google": .object([
            "groundingMetadata": .object([
                "groundingChunks": .array([
                    .object(["web": .object(["uri": .string("https://swift.org"), "title": .string("Swift.org")])]),
                    .object(["retrievedContext": .object([
                        "uri": .string("https://docs.example.com/swift"),
                        "title": .string("Swift Docs")
                    ])]),
                    .object(["image": .object([
                        "uri": .string("https://images.example.com/swift-logo.png"),
                        "title": .string("Swift Logo")
                    ])]),
                    .object(["maps": .object(["uri": .string("https://maps.example.com/apple-hq"), "title": .string("Apple HQ")])])
                ]),
                "webSearchQueries": .array([.string("Swift mixed sources")])
            ]),
            "safetyRatings": .array([
                .object([
                    "category": .string("HARM_CATEGORY_DANGEROUS_CONTENT"),
                    "probability": .string("NEGLIGIBLE"),
                    "blocked": .bool(false)
                ]),
                .object([
                    "category": .string("HARM_CATEGORY_HATE_SPEECH"),
                    "probability": .string("NEGLIGIBLE"),
                    "blocked": .bool(false)
                ])
            ]),
            "urlContextMetadata": .object([
                "urlMetadata": .array([
                    .object([
                        "url": .string("https://swift.org"),
                        "title": .string("Swift.org"),
                        "snippet": .string("Swift is a general-purpose programming language.")
                    ]),
                    .object([
                        "url": .string("https://docs.example.com/swift"),
                        "title": .string("Swift Docs"),
                        "snippet": .string("Official Swift documentation.")
                    ])
                ])
            ])
        ])
    ]
    return UIMessage(id: "msg-mixed", role: .assistant, metadata: metadata)
}
