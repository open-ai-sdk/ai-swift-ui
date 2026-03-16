/// A document source reference part of a UI message.
public struct SourceDocumentPart: Codable, Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var mediaType: String?
    public var url: String?
    /// Optional snippet or excerpt from the document.
    public var content: String?
    /// Original filename of the document.
    public var filename: String?

    public init(
        id: String? = nil,
        title: String? = nil,
        mediaType: String? = nil,
        url: String? = nil,
        content: String? = nil,
        filename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.mediaType = mediaType
        self.url = url
        self.content = content
        self.filename = filename
    }
}
