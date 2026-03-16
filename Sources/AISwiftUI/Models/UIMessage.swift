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
