import Foundation

/// The lifecycle state of a tool invocation within an assistant message.
public enum ToolState: String, Codable, Sendable, Equatable {
    /// Tool input is currently streaming.
    case inputStreaming
    /// Tool input is complete but execution has not yet finished.
    case inputAvailable
    /// Tool output is available (execution completed successfully).
    case outputAvailable
    /// Tool execution resulted in an error.
    case outputError
}

/// A tool invocation content part of a UI message.
public struct ToolInvocationPart: Codable, Sendable, Equatable {
    /// Unique call identifier issued by the model.
    public var toolCallId: String
    /// Name of the tool being invoked.
    public var toolName: String
    /// Current state of the invocation.
    public var state: ToolState
    /// Tool input arguments as a JSON-serializable value.
    public var input: JSONValue
    /// Tool output, present when `state` is `.outputAvailable` or `.outputError`.
    public var output: JSONValue?

    public init(
        toolCallId: String,
        toolName: String,
        state: ToolState,
        input: JSONValue,
        output: JSONValue? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.state = state
        self.input = input
        self.output = output
    }
}
