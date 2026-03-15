import Foundation

/// A single message in a chat conversation, rendered on the UI layer.
/// Messages accumulate `parts` as the assistant response streams in.
public struct UIMessage: Identifiable, Sendable, Equatable {
    public let id: String
    public var role: ChatRole
    public var parts: [UIMessagePart]
    public var createdAt: Date

    public init(
        id: String,
        role: ChatRole,
        parts: [UIMessagePart] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
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
}

// MARK: - Codable

extension UIMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, role, parts, createdAt
    }
}
