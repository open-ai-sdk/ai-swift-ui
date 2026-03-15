/// A custom data payload part of a UI message, emitted from a `data-*` chunk.
/// The `name` corresponds to the suffix after "data-" in the chunk type (e.g. "plan", "steps").
public struct DataPart: Codable, Sendable, Equatable {
    /// The data chunk name (e.g. "plan", "suggested-questions").
    public var name: String
    /// The decoded JSON payload.
    public var data: JSONValue

    public init(name: String, data: JSONValue) {
        self.name = name
        self.data = data
    }
}

// MARK: - Typed accessors for well-known data chunk payloads

public extension DataPart {

    /// Token usage from a `data-usage` chunk.
    /// Returns non-nil only when `name == "usage"` and the payload has the expected shape.
    var usageTokens: UsageTokens? {
        guard name == "usage", case .object(let obj) = data else { return nil }
        guard let prompt = obj["promptTokens"]?.intValue,
              let completion = obj["completionTokens"]?.intValue,
              let total = obj["totalTokens"]?.intValue else { return nil }
        return UsageTokens(promptTokens: prompt, completionTokens: completion, totalTokens: total)
    }

    /// Suggested follow-up questions from a `data-suggested-questions` chunk.
    /// Returns non-nil only when `name == "suggested-questions"` and payload has a `questions` array.
    var suggestedQuestions: [String]? {
        guard name == "suggested-questions",
              case .object(let obj) = data,
              case .array(let arr) = obj["questions"] else { return nil }
        return arr.compactMap(\.stringValue)
    }
}

/// Token usage counts decoded from a `data-usage` chunk payload.
public struct UsageTokens: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}
