# ai-swift-ui

SwiftUI client SDK for AI chat applications using the AI SDK UI message stream protocol.

## Features

- **Chat session** — `@MainActor @Observable ChatSession` with send, stop, regenerate, resubmit, message editing, and error handling
- **Smooth streaming** — word-level typewriter effect via `smoothStreamDelay`
- **Tool loop** — automatic client-side tool execution with `onToolCall`, `addToolResult`, `sendAutomaticallyWhen`
- **Attachments** — `PendingAttachment` staging + `AttachmentUploader` protocol
- **Auth** — `TokenProvider` protocol for async bearer token injection
- **Persistence** — `snapshot()` / `restore(from:)` + Codable message arrays
- **Rich parts** — text, reasoning, tool invocations, sources, files, images, custom data
- **HTTP transport** — configurable `HTTPChatTransport` with headers, `requestBuilder`, `TokenProvider`
- **Protocol-first** — `ChatTransport` protocol lets you swap in any network layer

## Requirements

- Swift 6.0+
- macOS 14+ / iOS 17+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/gnas-space/ai-sdk-go", from: "0.1.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "AISwiftUI", package: "ai-sdk-go")
    ])
]
```

## Quick Start

```swift
import AISwiftUI

let transport = HTTPChatTransport(
    apiURL: URL(string: "https://api.example.com/chat")!,
    headers: { ["Authorization": "Bearer \(token)"] }
)

let session = ChatSession(id: "conversation-1", transport: transport)
await session.send(.user(text: "Hello!"))

// SwiftUI — session.messages, session.status, session.error are all @Observable
```

## Package Structure

```
Sources/AISwiftUI/
  Session/      ChatSession, tool-loop, enhancements
  Transport/    ChatTransport, HTTPChatTransport, TokenProvider
  Stream/       UIMessageChunkDecoder, UIMessageStreamReducer, SmoothStreamAdapter
  Models/       UIMessage, UIMessagePart, ChatRole, ChatStatus, JSONValue, part types
  Attachments/  PendingAttachment, AttachmentUploader
  Persistence/  MessagePersistence
```

## License

MIT — see [LICENSE](LICENSE) for details.
