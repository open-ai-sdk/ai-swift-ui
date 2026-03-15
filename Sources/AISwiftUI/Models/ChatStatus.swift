/// The lifecycle state of a chat session.
public enum ChatStatus: String, Sendable, Equatable {
    /// Session is idle and ready to send messages.
    case ready
    /// A message has been submitted and is awaiting the first response chunk.
    case submitted
    /// The assistant response is actively streaming.
    case streaming
    /// An error occurred; `ChatSession.error` will be set.
    case error
}
