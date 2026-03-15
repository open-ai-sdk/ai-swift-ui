/// A reasoning/thinking content part of a UI message.
/// The `signature` field is set when the reasoning block has been redacted by the model.
public struct ReasoningPart: Codable, Sendable, Equatable {
    public var reasoning: String
    /// Opaque signature provided by the model when reasoning is summarized/redacted.
    public var signature: String?

    public init(reasoning: String, signature: String? = nil) {
        self.reasoning = reasoning
        self.signature = signature
    }
}
