# feat: UISpecView — generative UI via json-render SpecStream

This PR adds support for the [json-render](https://github.com/vercel-labs/json-render) protocol,
allowing an AI model to stream a live SwiftUI component tree directly into a chat message.

---

## What's new

### `UIRenderSpec` model ([UIRenderSpec.swift](Sources/AISwiftUI/Models/UIRenderSpec.swift))

Mirrors the json-render wire format exactly:

```
UIRenderSpec
  root: String?                       // ID of the root element
  elements: [String: UIRenderElement] // flat element map

UIRenderElement
  type: String      // e.g. "VStack", "Text", "Button"
  props: JSONValue  // component-specific props
  children: [String] // ordered child element IDs
```

The spec is stored as raw `JSONValue` inside `UIRenderSpecPart` so JSON Patch operations
can be applied without encode/decode round-trips. `.decoded` gives a typed `UIRenderSpec`
when ready to render.

### `JSONPatchApplicator` ([JSONPatchApplicator.swift](Sources/AISwiftUI/Stream/JSONPatchApplicator.swift))

RFC 6902 JSON Patch applied directly to `JSONValue`. Supports the three operations
used by SpecStream (`add`, `replace`, `remove`). Path parsing follows RFC 6901
(`~0`/`~1` unescaping, `-` append sentinel for arrays).

### `UIMessagePart.uiSpec` ([UIMessagePart.swift](Sources/AISwiftUI/Models/UIMessagePart.swift))

New case added to the existing enum:

```swift
case uiSpec(UIRenderSpecPart)  // type = "ui-spec"
```

Codable round-trips correctly with `"type": "ui-spec"`.

### Stream reducer integration ([UIMessageStreamReducer.swift](Sources/AISwiftUI/Stream/UIMessageStreamReducer.swift))

`data-ui-spec` chunks are now intercepted before the generic `DataPart` path.
Each chunk is either:
- a **JSON Patch operation** (`{"op":…, "path":…, "value":…}`) — applied incrementally to the accumulated spec
- a **full spec** — replaces the current spec entirely

A single `.uiSpec` part is upserted into the message on every chunk, so SwiftUI
diffs only what changed.

### `UISpecView` ([UISpecView.swift](Sources/AISwiftUI/UI/UISpecView.swift))

Drop-in SwiftUI view that renders a live `UIRenderSpecPart`:

```swift
UISpecView(spec: part) { actionName, props in
    handleAction(actionName, props)
}
```

Custom components slot in via a dictionary:

```swift
UISpecView(spec: part, components: [
    "ProductCard": { props, children in
        AnyView(ProductCardView(props: props))
    }
])
```

Built-in components: `Text`, `Button`, `VStack`, `HStack`, `ZStack`,
`ScrollView`, `List`, `Image`, `Spacer`, `Divider`.

The `onAction` closure is propagated via an `EnvironmentKey` so nested custom
components can dispatch actions without prop-drilling.

---

## Protocol compatibility

Tested against the json-render SpecStream format documented at
[json-render.dev/docs/ai-sdk](https://json-render.dev/docs/ai-sdk).

The server side (Node.js) emits `data-ui-spec` chunks through `createUIMessageStream`;
this SDK now consumes them correctly.

---

## What's not implemented yet

The following json-render features are defined in the protocol but not yet handled
on the Swift side. Happy to add them in follow-up PRs or take direction on priority:

| Feature | Node.js field | Notes |
|---|---|---|
| Spec-level state | `state` in `UIRenderSpec` | Initial state bag for dynamic props |
| Per-element event bindings | `on` in `UIRenderElement` | Only `Button.action` is wired today |
| Conditional visibility | `visible` in `UIRenderElement` | Show/hide based on state |
| Array repetition | `repeat` in `UIRenderElement` | Render list from state path |
| Dynamic prop expressions | `$state`, `$bindState`, `$computed`, `$cond` | Expression evaluation |
| Full JSON Patch ops | `move`, `copy`, `test` | Silently ignored; not emitted by SpecStream |

---

## Testing

- `JSONPatchApplicator` is covered by unit tests for all three operations across
  object and array targets, including nested paths and edge cases.
- `UIMessageStreamReducer` tests verify that `data-ui-spec` chunks land as a
  `.uiSpec` part and that incremental patches accumulate correctly.
