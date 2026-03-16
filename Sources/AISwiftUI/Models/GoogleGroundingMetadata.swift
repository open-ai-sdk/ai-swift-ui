import Foundation

/// A flattened grounding source from any chunk type.
public struct GroundingSource: Sendable, Equatable {
    public var type: String
    public var url: String
    public var title: String
}

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
    public var retrievedContext: RetrievedContextChunk?
    public var image: ImageChunk?
    public var maps: MapsChunk?

    public init(
        web: WebChunk? = nil,
        retrievedContext: RetrievedContextChunk? = nil,
        image: ImageChunk? = nil,
        maps: MapsChunk? = nil
    ) {
        self.web = web
        self.retrievedContext = retrievedContext
        self.image = image
        self.maps = maps
    }
}

public struct RetrievedContextChunk: Codable, Sendable, Equatable {
    public var uri: String?
    public var title: String?

    public init(uri: String? = nil, title: String? = nil) {
        self.uri = uri
        self.title = title
    }
}

public struct ImageChunk: Codable, Sendable, Equatable {
    public var uri: String?
    public var title: String?

    public init(uri: String? = nil, title: String? = nil) {
        self.uri = uri
        self.title = title
    }
}

public struct MapsChunk: Codable, Sendable, Equatable {
    public var uri: String?
    public var title: String?

    public init(uri: String? = nil, title: String? = nil) {
        self.uri = uri
        self.title = title
    }
}

public struct GoogleSafetyRating: Codable, Sendable, Equatable {
    public var category: String?
    public var probability: String?
    public var blocked: Bool?

    public init(category: String? = nil, probability: String? = nil, blocked: Bool? = nil) {
        self.category = category
        self.probability = probability
        self.blocked = blocked
    }
}

public struct GoogleURLContextMetadata: Codable, Sendable, Equatable {
    public var urlMetadata: [URLMetadataEntry]?

    public init(urlMetadata: [URLMetadataEntry]? = nil) {
        self.urlMetadata = urlMetadata
    }
}

public struct URLMetadataEntry: Codable, Sendable, Equatable {
    public var url: String?
    public var title: String?
    public var snippet: String?

    public init(url: String? = nil, title: String? = nil, snippet: String? = nil) {
        self.url = url
        self.title = title
        self.snippet = snippet
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
