/// A discriminated union of all possible content parts within a `UIMessage`.
public enum UIMessagePart: Sendable, Equatable {
    case text(TextPart)
    case reasoning(ReasoningPart)
    case toolInvocation(ToolInvocationPart)
    case sourceURL(SourceURLPart)
    case sourceDocument(SourceDocumentPart)
    case file(FilePart)
    case image(FilePart)
    case data(DataPart)
    /// A live json-render UI spec, built incrementally from SpecStream patches.
    case uiSpec(UIRenderSpecPart)
}

// MARK: - Codable

extension UIMessagePart: Codable {
    private enum PartType: String, Codable {
        case text
        case reasoning
        case toolInvocation = "tool-invocation"
        case sourceURL = "source-url"
        case sourceDocument = "source-document"
        case file
        case image
        case data
        case uiSpec = "ui-spec"
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(PartType.self, forKey: .type)
        switch type_ {
        case .text:
            self = .text(try TextPart(from: decoder))
        case .reasoning:
            self = .reasoning(try ReasoningPart(from: decoder))
        case .toolInvocation:
            self = .toolInvocation(try ToolInvocationPart(from: decoder))
        case .sourceURL:
            self = .sourceURL(try SourceURLPart(from: decoder))
        case .sourceDocument:
            self = .sourceDocument(try SourceDocumentPart(from: decoder))
        case .file:
            self = .file(try FilePart(from: decoder))
        case .image:
            self = .image(try FilePart(from: decoder))
        case .data:
            self = .data(try DataPart(from: decoder))
        case .uiSpec:
            self = .uiSpec(try UIRenderSpecPart(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.text, forKey: .type)
            try p.encode(to: encoder)
        case .reasoning(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.reasoning, forKey: .type)
            try p.encode(to: encoder)
        case .toolInvocation(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.toolInvocation, forKey: .type)
            try p.encode(to: encoder)
        case .sourceURL(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.sourceURL, forKey: .type)
            try p.encode(to: encoder)
        case .sourceDocument(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.sourceDocument, forKey: .type)
            try p.encode(to: encoder)
        case .file(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.file, forKey: .type)
            try p.encode(to: encoder)
        case .image(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.image, forKey: .type)
            try p.encode(to: encoder)
        case .data(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.data, forKey: .type)
            try p.encode(to: encoder)
        case .uiSpec(let p):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PartType.uiSpec, forKey: .type)
            try p.encode(to: encoder)
        }
    }
}
