import SwiftUI

// MARK: - Public API

/// A closure that renders a custom component from its props and resolved child views.
public typealias UISpecComponentBuilder = @Sendable (JSONValue, [AnyView]) -> AnyView

/// SwiftUI view that renders a `UIRenderSpecPart` produced by the json-render protocol.
///
/// ```swift
/// UISpecView(spec: part) { actionName, props in
///     handleAction(actionName, props)
/// }
/// ```
///
/// Register custom components via the `components` dictionary to map
/// json-render type names to SwiftUI builders:
///
/// ```swift
/// UISpecView(spec: part, components: [
///     "ProductCard": { props, children in
///         AnyView(ProductCardView(props: props))
///     }
/// ])
/// ```
public struct UISpecView: View {
    public let spec: UIRenderSpecPart
    public let components: [String: UISpecComponentBuilder]
    public let onAction: (@Sendable (String, JSONValue) -> Void)?

    public init(
        spec: UIRenderSpecPart,
        components: [String: UISpecComponentBuilder] = [:],
        onAction: (@Sendable (String, JSONValue) -> Void)? = nil
    ) {
        self.spec = spec
        self.components = components
        self.onAction = onAction
    }

    public var body: some View {
        if let rootId = spec.rawValue["root"]?.stringValue {
            UISpecElementView(elementId: rootId, specData: spec.rawValue, components: components)
                .environment(\.uiSpecAction, onAction)
        }
    }
}

// MARK: - Environment key for action dispatch

private struct UISpecActionKey: EnvironmentKey {
    static let defaultValue: (@Sendable (String, JSONValue) -> Void)? = nil
}

extension EnvironmentValues {
    /// The action handler injected by `UISpecView`. Read this inside custom component builders.
    public var uiSpecAction: (@Sendable (String, JSONValue) -> Void)? {
        get { self[UISpecActionKey.self] }
        set { self[UISpecActionKey.self] = newValue }
    }
}

// MARK: - Recursive element renderer

struct UISpecElementView: View {
    let elementId: String
    let specData: JSONValue
    let components: [String: UISpecComponentBuilder]

    @Environment(\.uiSpecAction) private var onAction

    private var element: JSONValue? { specData["elements"]?[elementId] }
    private var elementType: String { element?["type"]?.stringValue ?? "" }
    private var props: JSONValue { element?["props"] ?? .null }

    private var childIds: [String] {
        element?["children"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private var childViews: [AnyView] {
        childIds.map { id in
            AnyView(UISpecElementView(elementId: id, specData: specData, components: components))
        }
    }

    var body: some View {
        if element == nil {
            EmptyView()
        } else if let builder = components[elementType] {
            builder(props, childViews)
        } else {
            BuiltinUIElement(type: elementType, props: props, childViews: childViews, onAction: onAction)
        }
    }
}

// MARK: - Built-in component renderer

private struct BuiltinUIElement: View {
    let type: String
    let props: JSONValue
    let childViews: [AnyView]
    let onAction: (@Sendable (String, JSONValue) -> Void)?

    var body: some View {
        switch type {
        case "Text", "Label":
            textView

        case "Button":
            buttonView

        case "VStack":
            VStack(
                alignment: hAlignment(props["alignment"]?.stringValue),
                spacing: cgFloat(props["spacing"])
            ) {
                childrenView
            }
            .modifier(PaddingModifier(props: props))

        case "HStack":
            HStack(
                alignment: vAlignment(props["alignment"]?.stringValue),
                spacing: cgFloat(props["spacing"])
            ) {
                childrenView
            }
            .modifier(PaddingModifier(props: props))

        case "ZStack":
            ZStack {
                childrenView
            }

        case "ScrollView":
            ScrollView {
                VStack(spacing: 0) {
                    childrenView
                }
            }

        case "List":
            VStack(alignment: .leading, spacing: 0) {
                childrenView
            }

        case "Image":
            imageView

        case "Spacer":
            Spacer(minLength: cgFloat(props["minLength"]))

        case "Divider":
            Divider()

        default:
            // Unknown type — render children vertically so nothing is lost
            VStack(alignment: .leading, spacing: cgFloat(props["spacing"])) {
                childrenView
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder private var textView: some View {
        let content = props["text"]?.stringValue
            ?? props["content"]?.stringValue
            ?? props["label"]?.stringValue
            ?? ""
        Text(content)
            .font(swiftUIFont(props["textStyle"]?.stringValue ?? props["fontSize"]?.stringValue))
            .fontWeight(fontWeight(props["fontWeight"]?.stringValue))
            .foregroundColor(swiftUIColor(props["color"]?.stringValue ?? props["foregroundColor"]?.stringValue))
            .multilineTextAlignment(textAlignment(props["textAlignment"]?.stringValue))
            .lineLimit(props["lineLimit"]?.intValue)
    }

    @ViewBuilder private var buttonView: some View {
        Button {
            let actionName = props["action"]?.stringValue ?? "tap"
            onAction?(actionName, props)
        } label: {
            if !childViews.isEmpty {
                childrenView
            } else {
                Text(props["title"]?.stringValue ?? props["label"]?.stringValue ?? "")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(swiftUIColor(props["tint"]?.stringValue))
    }

    @ViewBuilder private var imageView: some View {
        if let systemName = props["systemName"]?.stringValue {
            Image(systemName: systemName)
                .foregroundColor(swiftUIColor(props["color"]?.stringValue))
        } else if let name = props["name"]?.stringValue {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
        }
    }

    @ViewBuilder private var childrenView: some View {
        ForEach(Array(childViews.enumerated()), id: \.offset) { _, child in
            child
        }
    }

    // MARK: - Prop helpers

    private func cgFloat(_ value: JSONValue?) -> CGFloat? {
        guard let value else { return nil }
        if let d = value.doubleValue { return CGFloat(d) }
        return nil
    }

    private func hAlignment(_ value: String?) -> HorizontalAlignment {
        switch value {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }

    private func vAlignment(_ value: String?) -> VerticalAlignment {
        switch value {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    private func textAlignment(_ value: String?) -> TextAlignment {
        switch value {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }

    private func swiftUIFont(_ value: String?) -> Font? {
        switch value {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "body": return .body
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption": return .caption
        case "caption2": return .caption2
        default: return nil
        }
    }

    private func fontWeight(_ value: String?) -> Font.Weight? {
        switch value {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return nil
        }
    }

    private func swiftUIColor(_ value: String?) -> Color? {
        switch value {
        case "primary": return .primary
        case "secondary": return .secondary
        case "accentColor": return .accentColor
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray": return .gray
        case "white": return .white
        case "black": return .black
        default: return nil
        }
    }
}

// MARK: - Padding view modifier

private struct PaddingModifier: ViewModifier {
    let props: JSONValue

    func body(content: Content) -> some View {
        if let all = props["padding"]?.doubleValue {
            content.padding(CGFloat(all))
        } else if props["padding"] != nil {
            content.padding()
        } else {
            content
        }
    }
}
