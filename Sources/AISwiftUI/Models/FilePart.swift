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
    /// Gemini 3 thought signature for multi-turn image editing.
    public var thoughtSignature: String?

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

// MARK: - Image convenience

public extension FilePart {
    /// Whether this file part represents an image (based on media type).
    var isImage: Bool {
        mediaType.hasPrefix("image/")
    }

    /// Extracts image binary data from inline `data` field or from a `data:` URL.
    var imageData: Data? {
        if let data { return data }
        guard url.hasPrefix("data:"),
              let base64Range = url.range(of: ";base64,") else { return nil }
        let base64String = String(url[base64Range.upperBound...])
        return Data(base64Encoded: base64String)
    }
}
