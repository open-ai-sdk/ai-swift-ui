import Foundation

/// Typed model for Google grounding metadata from Gemini search results.
public struct GoogleGroundingMetadata: Codable, Sendable, Equatable {
    public var groundingChunks: [GroundingChunk]?
    public var groundingSupports: [GroundingSupport]?
    public var webSearchQueries: [String]?
    public var searchEntryPoint: SearchEntryPoint?

    public init(
        groundingChunks: [GroundingChunk]? = nil,
        groundingSupports: [GroundingSupport]? = nil,
        webSearchQueries: [String]? = nil,
        searchEntryPoint: SearchEntryPoint? = nil
    ) {
        self.groundingChunks = groundingChunks
        self.groundingSupports = groundingSupports
        self.webSearchQueries = webSearchQueries
        self.searchEntryPoint = searchEntryPoint
    }
}

public struct GroundingChunk: Codable, Sendable, Equatable {
    public var web: WebChunk?

    public init(web: WebChunk? = nil) {
        self.web = web
    }
}

public struct WebChunk: Codable, Sendable, Equatable {
    public var uri: String?
    public var title: String?

    public init(uri: String? = nil, title: String? = nil) {
        self.uri = uri
        self.title = title
    }
}

public struct GroundingSupport: Codable, Sendable, Equatable {
    public var segment: GroundingSegment?
    public var groundingChunkIndices: [Int]?
    public var confidenceScores: [Double]?

    public init(
        segment: GroundingSegment? = nil,
        groundingChunkIndices: [Int]? = nil,
        confidenceScores: [Double]? = nil
    ) {
        self.segment = segment
        self.groundingChunkIndices = groundingChunkIndices
        self.confidenceScores = confidenceScores
    }
}

public struct GroundingSegment: Codable, Sendable, Equatable {
    public var startIndex: Int?
    public var endIndex: Int?
    public var text: String?

    public init(startIndex: Int? = nil, endIndex: Int? = nil, text: String? = nil) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.text = text
    }
}

public struct SearchEntryPoint: Codable, Sendable, Equatable {
    public var renderedContent: String?

    public init(renderedContent: String? = nil) {
        self.renderedContent = renderedContent
    }
}
