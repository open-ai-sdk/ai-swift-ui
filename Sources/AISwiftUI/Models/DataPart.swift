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
