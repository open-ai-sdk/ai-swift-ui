/// A web URL source reference part of a UI message.
public struct SourceURLPart: Codable, Sendable, Equatable {
    public var id: String?
    public var url: String
    public var title: String?

    public init(id: String? = nil, url: String, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }
}
