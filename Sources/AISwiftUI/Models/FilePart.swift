/// A file attachment part of a UI message.
public struct FilePart: Codable, Sendable, Equatable {
    /// The URL or data URI of the file.
    public var url: String
    /// MIME type (e.g. "application/pdf", "image/png").
    public var mediaType: String
    /// Original filename, if available.
    public var name: String?

    public init(url: String, mediaType: String, name: String? = nil) {
        self.url = url
        self.mediaType = mediaType
        self.name = name
    }
}
