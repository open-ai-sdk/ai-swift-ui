import Foundation

/// The top-level spec produced by the json-render protocol.
/// Contains a reference to the root element and a flat map of all elements.
public struct UIRenderSpec: Codable, Sendable, Equatable {
    /// ID of the root element to render.
    public var root: String?
    /// Flat map of element ID → element definition.
    public var elements: [String: UIRenderElement]

    public init(root: String? = nil, elements: [String: UIRenderElement] = [:]) {
        self.root = root
        self.elements = elements
    }
}

/// A single node in the json-render element tree.
public struct UIRenderElement: Codable, Sendable, Equatable {
    /// Component type name (e.g. "Text", "VStack", "Button").
    public var type: String
    /// Typed component props as a JSON value.
    public var props: JSONValue
    /// Ordered list of child element IDs.
    public var children: [String]

    public init(type: String, props: JSONValue = .null, children: [String] = []) {
        self.type = type
        self.props = props
        self.children = children
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, props, children
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        props = (try? container.decode(JSONValue.self, forKey: .props)) ?? .null
        children = (try? container.decode([String].self, forKey: .children)) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(props, forKey: .props)
        try container.encode(children, forKey: .children)
    }
}

/// A `UIMessagePart` payload carrying a live json-render spec.
///
/// The spec is stored as a raw `JSONValue` so that JSON Patch operations
/// can be applied incrementally without encode/decode round-trips.
/// Use `decoded` to get a typed `UIRenderSpec` when ready to render.
public struct UIRenderSpecPart: Codable, Sendable, Equatable {
    /// The accumulated spec as a JSON value (may be partially built during streaming).
    public var rawValue: JSONValue

    public init(rawValue: JSONValue = .object([:])) {
        self.rawValue = rawValue
    }

    /// Decodes the raw value into a typed `UIRenderSpec`.
    public var decoded: UIRenderSpec? {
        guard let data = try? JSONEncoder().encode(rawValue) else { return nil }
        return try? JSONDecoder().decode(UIRenderSpec.self, from: data)
    }
}
