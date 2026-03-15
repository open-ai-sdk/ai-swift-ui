import Foundation

/// A value type used to create new outgoing user messages before appending to a session.
public struct NewUIMessage: Sendable {
    public var role: ChatRole
    public var text: String
    public var files: [FilePart]

    public init(role: ChatRole = .user, text: String, files: [FilePart] = []) {
        self.role = role
        self.text = text
        self.files = files
    }

    /// Convenience factory for a plain user text message.
    public static func user(text: String, files: [FilePart] = []) -> NewUIMessage {
        NewUIMessage(role: .user, text: text, files: files)
    }

    /// Converts this value into a full `UIMessage` with a new UUID.
    public func makeMessage(id: String = UUID().uuidString, createdAt: Date = Date()) -> UIMessage {
        var parts: [UIMessagePart] = [.text(TextPart(text: text))]
        parts += files.map { .file($0) }
        return UIMessage(id: id, role: role, parts: parts, createdAt: createdAt)
    }
}
