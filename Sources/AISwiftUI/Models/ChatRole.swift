/// The role of a participant in a chat conversation.
public enum ChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}
