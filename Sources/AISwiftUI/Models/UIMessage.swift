import Foundation

/// A single message in a chat conversation, rendered on the UI layer.
/// Messages accumulate `parts` as the assistant response streams in.
public struct UIMessage: Identifiable, Sendable, Equatable {
    public let id: String
    public var role: ChatRole
    public var parts: [UIMessagePart]
    public var createdAt: Date
    /// Message-level metadata from a `message-metadata` chunk.
    public var metadata: [String: JSONValue]?

    public init(
        id: String,
        role: ChatRole,
        parts: [UIMessagePart] = [],
        createdAt: Date = Date(),
        metadata: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

// MARK: - Computed helpers

public extension UIMessage {
    /// The concatenated text from all `.text` parts.
    var primaryText: String {
        parts.compactMap {
            if case .text(let p) = $0 { return p.text }
            return nil
        }.joined()
    }

    /// All tool invocation parts in order.
    var toolInvocations: [ToolInvocationPart] {
        parts.compactMap {
            if case .toolInvocation(let p) = $0 { return p }
            return nil
        }
    }

    /// All source URL and document parts in order.
    var sources: [UIMessagePart] {
        parts.filter {
            if case .sourceURL = $0 { return true }
            if case .sourceDocument = $0 { return true }
            return false
        }
    }

    /// All data parts in order.
    var dataParts: [DataPart] {
        parts.compactMap {
            if case .data(let p) = $0 { return p }
            return nil
        }
    }

    /// Document references decoded from `data-document-references` chunks.
    var documentReferences: [SourceDocumentPart] {
        parts.compactMap {
            if case .sourceDocument(let p) = $0 { return p }
            return nil
        }
    }

    /// Parts suitable for persistence (filters out transient data parts).
    var persistableParts: [UIMessagePart] {
        parts.filter { part in
            if case .data(let dp) = part, dp.isTransient { return false }
            return true
        }
    }

    /// Extracts typed Google grounding metadata from the message metadata dictionary.
    var googleGroundingMetadata: GoogleGroundingMetadata? {
        guard let meta = metadata,
              case .object(let googleObj) = meta["google"],
              case .object(let gmObj) = googleObj["groundingMetadata"] else {
            return nil
        }
        let nsObj = JSONValue.object(gmObj).rawValue
        guard let data = try? JSONSerialization.data(withJSONObject: nsObj) else { return nil }
        return try? JSONDecoder().decode(GoogleGroundingMetadata.self, from: data)
    }

    /// Web search queries used for grounding.
    var groundingSearchQueries: [String]? {
        googleGroundingMetadata?.webSearchQueries
    }

    /// Grounded source URLs with titles.
    var groundingSources: [(url: String, title: String)]? {
        googleGroundingMetadata?.groundingChunks?.compactMap { chunk in
            guard let web = chunk.web, let uri = web.uri else { return nil }
            return (url: uri, title: web.title ?? "")
        }
    }

    /// Safety ratings from Google provider metadata.
    var googleSafetyRatings: [GoogleSafetyRating]? {
        guard let meta = metadata,
              case .object(let googleObj) = meta["google"],
              let ratingsValue = googleObj["safetyRatings"],
              case .array(let ratingsArr) = ratingsValue else { return nil }
        let nsObj = JSONValue.array(ratingsArr).rawValue
        guard let data = try? JSONSerialization.data(withJSONObject: nsObj) else { return nil }
        return try? JSONDecoder().decode([GoogleSafetyRating].self, from: data)
    }

    /// URL context metadata from Google provider.
    var googleURLContextMetadata: GoogleURLContextMetadata? {
        guard let meta = metadata,
              case .object(let googleObj) = meta["google"],
              let urlCtxValue = googleObj["urlContextMetadata"],
              case .object(let urlCtxObj) = urlCtxValue else { return nil }
        let nsObj = JSONValue.object(urlCtxObj).rawValue
        guard let data = try? JSONSerialization.data(withJSONObject: nsObj) else { return nil }
        return try? JSONDecoder().decode(GoogleURLContextMetadata.self, from: data)
    }

    /// All grounding sources (web + retrieved-context + image + maps) as a flat list.
    /// Merges sources from Google grounding metadata AND explicit `source-url` stream chunks.
    var allGroundingSources: [GroundingSource]? {
        var results: [GroundingSource] = []
        var seen = Set<String>()

        // 1. Sources from Google grounding metadata (message-metadata chunk).
        if let chunks = googleGroundingMetadata?.groundingChunks {
            for chunk in chunks {
                if let web = chunk.web, let uri = web.uri {
                    if seen.insert(uri).inserted {
                        results.append(GroundingSource(type: "url", url: uri, title: web.title ?? ""))
                    }
                } else if let rc = chunk.retrievedContext, let uri = rc.uri {
                    if seen.insert(uri).inserted {
                        results.append(GroundingSource(type: "retrieved-context", url: uri, title: rc.title ?? ""))
                    }
                } else if let img = chunk.image, let uri = img.uri {
                    if seen.insert(uri).inserted {
                        results.append(GroundingSource(type: "image", url: uri, title: img.title ?? ""))
                    }
                } else if let maps = chunk.maps, let uri = maps.uri {
                    if seen.insert(uri).inserted {
                        results.append(GroundingSource(type: "maps", url: uri, title: maps.title ?? ""))
                    }
                }
            }
        }

        // 2. Sources from explicit source-url stream chunks (native Gemini SSE path).
        for part in parts {
            if case .sourceURL(let src) = part, !src.url.isEmpty {
                if seen.insert(src.url).inserted {
                    results.append(GroundingSource(type: "url", url: src.url, title: src.title ?? ""))
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    /// Usage token counts if a `data-usage` chunk was received.
    var usageTokens: UsageTokens? {
        dataParts.compactMap(\.usageTokens).first
    }

    /// Suggested follow-up questions if a `data-suggested-questions` chunk was received.
    var suggestedQuestions: [String]? {
        dataParts.compactMap(\.suggestedQuestions).first
    }
}

// MARK: - Codable

extension UIMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, role, parts, createdAt, metadata
    }
}
