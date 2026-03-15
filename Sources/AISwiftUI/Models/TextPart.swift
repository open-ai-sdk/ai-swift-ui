/// A plain-text content part of a UI message.
public struct TextPart: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}
