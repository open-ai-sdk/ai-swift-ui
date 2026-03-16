/// A custom data payload part of a UI message, emitted from a `data-*` chunk.
/// The `name` corresponds to the suffix after "data-" in the chunk type (e.g. "plan", "steps").
public struct DataPart: Codable, Sendable, Equatable {
    /// The data chunk name (e.g. "plan", "suggested-questions").
    public var name: String
    /// The decoded JSON payload.
    public var data: JSONValue
    /// When `true`, this part is transient and should not be persisted to history.
    public var isTransient: Bool
    /// Optional identifier for reconciliation across updates.
    public var id: String?

    public init(name: String, data: JSONValue, isTransient: Bool = false, id: String? = nil) {
        self.name = name
        self.data = data
        self.isTransient = isTransient
        self.id = id
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

    /// Research plan text from a `data-plan` chunk.
    /// Returns non-nil only when `name == "plan"`.
    var researchPlan: String? {
        guard name == "plan" else { return nil }
        return data.stringValue
    }

    /// Research steps list from a `data-steps` chunk.
    /// Returns non-nil only when `name == "steps"` and payload is an array of strings.
    var researchSteps: [String]? {
        guard name == "steps", case .array(let arr) = data else { return nil }
        return arr.compactMap(\.stringValue)
    }
}

/// Token usage counts decoded from a `data-usage` chunk payload.
public struct UsageTokens: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}
