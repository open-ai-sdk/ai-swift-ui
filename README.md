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

```swift
let transport = HTTPChatTransport(
    apiURL: apiURL,
    headers: { ["Authorization": "Bearer \(token)"] },
    requestBuilder: { request in
        var body: [String: Any] = [
            "messages": request.messages.map { $0.toDictionary() }
        ]
        if let metadata = request.options?.metadata {
            body.merge(metadata) { _, new in new }
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
)
```

### Callbacks

```swift
session.onFinish = { message in
    // Save to database
}
session.onError = { error in
    // Log error
}
session.onDataPart = { name, payload in
    // Handle custom data-* chunks (e.g., "plan", "sources")
}
```

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
