# ai-swift-ui

SwiftUI client SDK for AI chat applications using the AI SDK UI message stream protocol.

## Features

- **Chat models** — `UIMessage`, `UIMessagePart` with text, reasoning, tool invocations, sources, files, and custom data
- **Stream decoding** — SSE chunk decoder and stateful reducer that builds `UIMessage` from streaming chunks
- **HTTP transport** — Configurable `HTTPChatTransport` with custom headers, request builder, and auth support
- **Chat session** — `@MainActor @Observable ChatSession` with send, stop, regenerate, and error handling
- **Protocol-first** — Decodes the standard AI SDK UI message stream format, compatible with any backend emitting it

## Package Structure

```
Sources/AISwiftUI/
  Models/       UIMessage, UIMessagePart, ChatRole, ChatStatus, part types
  Stream/       UIMessageChunkDecoder, UIMessageStreamReducer
  Transport/    ChatTransport protocol, HTTPChatTransport
  Session/      ChatSession (@MainActor @Observable)
```

## Quick Start

```swift
import AISwiftUI

// Configure transport
let transport = HTTPChatTransport(
    apiURL: URL(string: "https://api.example.com/chat")!,
    headers: { ["Authorization": "Bearer \(token)"] }
)

// Create session
let session = ChatSession(
    id: "conversation-1",
    transport: transport
)

// Send a message
await session.send(.user(text: "Hello!"))

// Observe in SwiftUI
struct ChatView: View {
    let session: ChatSession

    var body: some View {
        List(session.messages) { message in
            MessageRow(message: message)
        }
    }
}
```

### Custom Request Body

Use `requestBuilder` to reshape the body for backends that expect a different envelope:

```swift
let transport = HTTPChatTransport(
    apiURL: URL(string: "https://api.example.com/chat")!,
    headers: { ["Authorization": "Bearer \(token)"] },
    requestBuilder: { request, urlRequest in
        var body: [String: Any] = [
            "id": request.id,
            "messages": request.messages.map { msg in
                ["role": msg.role.rawValue, "content": msg.primaryText]
            }
        ]
        // Merge app-specific fields from options.body
        if let extra = request.options?.body {
            for (k, v) in extra { body[k] = v }
        }
        var req = urlRequest
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
)
```

The `requestBuilder` receives both the `TransportSendRequest` (with `id`, `messages`, `options`) and the pre-configured `URLRequest` (method, URL, default headers already set). Modify and return the request.

### Callbacks

```swift
session.onFinish = { message in
    // Persist completed assistant message
}
session.onError = { error in
    // Report to error tracker
}
session.onDataPart = { name, payload in
    // Handle custom data-* chunks from the server
    // name: the suffix after "data-" (e.g. "usage", "document-references")
    // payload: Any (the decoded JSONValue.rawValue)
}
```

### Custom Data Handling

The server can emit `data-{name}` chunks alongside the regular stream. These arrive as `UIMessagePart.data(DataPart)` on the assistant message and also fire the `onDataPart` callback.

```swift
// Reading data parts after stream completes:
session.onFinish = { message in
    for part in message.dataParts {
        switch part.name {
        case "usage":
            if case .object(let d) = part.data,
               case .number(let total) = d["totalTokens"] {
                print("tokens used: \(total)")
            }
        case "document-references":
            if case .array(let docs) = part.data {
                // Each element is a JSONValue describing a document
                handleDocumentReferences(docs)
            }
        default:
            break
        }
    }
}

// Or react in real-time via onDataPart:
session.onDataPart = { name, payload in
    if name == "document-references",
       let refs = payload as? [[String: Any]] {
        DispatchQueue.main.async { self.documentReferences = refs }
    }
}
```

`DataPart.data` is typed as `JSONValue` — a recursive enum with cases `.string`, `.number`, `.bool`, `.null`, `.array([JSONValue])`, `.object([String: JSONValue])`.

### Integration with Backend

For backends that use the canonical `uistream.ChatRequestEnvelope` from `ai-go`:

```swift
// The default HTTPChatTransport body matches the envelope:
// { "id": session.id, "messages": [...] }
// Extra body fields merge in alongside messages:
let options = ChatRequestOptions(
    body: [
        "modelId": selectedModelId as Any,
        "agentId": selectedAgentId as Any,
        "runId": UUID().uuidString
    ],
    metadata: ["threadId": conversationID]
)
await session.send(.user(text: inputText), options: options)
```

For legacy backends that expect a different shape, use `requestBuilder` as shown above — it gives full control over the `URLRequest` while still receiving the structured `TransportSendRequest`.

## Message Parts

| Part | Description |
|------|-------------|
| `TextPart` | Accumulated text content |
| `ReasoningPart` | Model reasoning/thinking with optional signature |
| `ToolInvocationPart` | Tool call lifecycle (streaming → available → output) |
| `SourceURLPart` | Web search result URL reference |
| `SourceDocumentPart` | Document/file reference metadata |
| `FilePart` | Attached file with URL and MIME type |
| `DataPart` | Custom `data-*` chunk with arbitrary JSON payload |

## Requirements

- Swift 6.0+
- macOS 14+ / iOS 17+

## License

MIT — see [LICENSE](LICENSE) for details.
