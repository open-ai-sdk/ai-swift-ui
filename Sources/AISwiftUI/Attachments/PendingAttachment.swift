import Foundation

/// A file or image awaiting upload before being attached to a chat message.
public struct PendingAttachment: Identifiable, Sendable, Equatable {
    public let id: String
    public let data: Data
    public let filename: String
    public let mimeType: String

    public init(
        id: String = UUID().uuidString,
        data: Data,
        filename: String,
        mimeType: String
    ) {
        self.id = id
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}
