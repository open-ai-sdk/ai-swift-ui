import Foundation

/// A file attachment part of a UI message.
/// Supports three content modes (priority order): fileId > data > url.
public struct FilePart: Codable, Sendable, Equatable {
    /// The URL or data URI of the file (empty string when fileId/data mode is used).
    public var url: String
    /// MIME type (e.g. "application/pdf", "image/png").
    public var mediaType: String
    /// Original filename, if available.
    public var name: String?
    /// Provider-side file identifier (e.g. OpenAI file ID).
    public var fileId: String?
    /// Inline binary content. Encoded as base64 in JSON.
    public var data: Data?

    /// URL mode initializer (backwards compatible).
    public init(url: String, mediaType: String, name: String? = nil) {
        self.url = url
        self.mediaType = mediaType
        self.name = name
    }

    /// Creates a FilePart using a provider file ID.
    public static func withFileId(_ fileId: String, mediaType: String, name: String? = nil) -> FilePart {
        var fp = FilePart(url: "", mediaType: mediaType, name: name)
        fp.fileId = fileId
        return fp
    }

    /// Creates a FilePart using inline binary data.
    public static func withData(_ data: Data, mediaType: String, name: String? = nil) -> FilePart {
        var fp = FilePart(url: "", mediaType: mediaType, name: name)
        fp.data = data
        return fp
    }
}
