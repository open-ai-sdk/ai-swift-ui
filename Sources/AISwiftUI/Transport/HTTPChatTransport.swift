import Foundation

/// A `ChatTransport` implementation that sends requests over HTTP/SSE using `URLSession`.
///
/// The transport is configurable via:
/// - `apiURL`: the endpoint to POST to
/// - `headers`: a closure returning static or dynamic headers (e.g. auth tokens)
/// - `prepareSendRequest`: optional async hook to customize messages, body, headers, and URL
/// - `requestBuilder`: optional closure to fully customize the `URLRequest` before sending
///
/// By default the transport encodes the request body as the canonical
/// `ChatRequestEnvelope`-shaped JSON using `JSONEncoder`. Supply a `requestBuilder` to
/// reshape the body for app-specific backends.
public final class HTTPChatTransport: ChatTransport, @unchecked Sendable {

    /// The API endpoint URL.
    public let apiURL: URL

    /// Returns headers to attach to every request (e.g. Authorization).
    public var headers: @Sendable () -> [String: String]

    /// Optional async hook to customize messages, body, headers, and URL before the request fires.
    /// Runs before `requestBuilder`. Return a modified `PreparedSendRequest`.
    public var prepareSendRequest: (@Sendable (PreparedSendRequest) async throws -> PreparedSendRequest)?

    /// Optional hook to fully customize the `URLRequest` before it is sent.
    /// Return the modified request. Runs after `prepareSendRequest`.
    public var requestBuilder: (@Sendable (TransportSendRequest, URLRequest) throws -> URLRequest)?

    /// Optional token provider for injecting `Authorization: Bearer <token>` headers.
    public var tokenProvider: (any TokenProvider)?

    private let session: URLSession
    private let decoder = UIMessageChunkDecoder()

    public init(
        apiURL: URL,
        tokenProvider: (any TokenProvider)? = nil,
        headers: @escaping @Sendable () -> [String: String] = { [:] },
        prepareSendRequest: (@Sendable (PreparedSendRequest) async throws -> PreparedSendRequest)? = nil,
        requestBuilder: (@Sendable (TransportSendRequest, URLRequest) throws -> URLRequest)? = nil,
        session: URLSession = .shared
    ) {
        self.apiURL = apiURL
        self.headers = headers
        self.prepareSendRequest = prepareSendRequest
        self.requestBuilder = requestBuilder
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try await self.buildURLRequestAsync(for: request)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200..<300).contains(httpResponse.statusCode) {
                        throw TransportError.httpError(statusCode: httpResponse.statusCode)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let chunk = try self.decoder.decode(line) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internal helpers (accessible via @testable import)

    func buildURLRequestAsync(for request: TransportSendRequest) async throws -> URLRequest {
        // 1. Build PreparedSendRequest from TransportSendRequest + transport defaults
        var prepared = PreparedSendRequest(
            api: apiURL,
            chatId: request.id,
            messages: request.messages,
            body: request.options?.body ?? [:],
            headers: headers()
        )
        // Merge per-request headers
        if let perRequest = request.options?.headers {
            for (key, value) in perRequest {
                prepared.headers[key] = value
            }
        }

        // 2. Run prepareSendRequest hook if set (async, so only in async path)
        if let hook = prepareSendRequest {
            prepared = try await hook(prepared)
        }

        // 3. Build URLRequest from PreparedSendRequest
        var urlRequest = URLRequest(url: prepared.api)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in prepared.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // 4. Apply token provider
        if let provider = tokenProvider, let token = try await provider.accessToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 5. requestBuilder escape hatch (URLRequest-level customization)
        if let customBuilder = requestBuilder {
            return try customBuilder(request, urlRequest)
        }

        // 6. Default body encoding via JSONEncoder + Codable envelope
        urlRequest.httpBody = try encodeBody(prepared: prepared, request: request)
        return urlRequest
    }

    func buildURLRequest(for request: TransportSendRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Apply static headers
        for (key, value) in headers() {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Apply per-request headers
        if let perRequest = request.options?.headers {
            for (key, value) in perRequest {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let customBuilder = requestBuilder {
            return try customBuilder(request, urlRequest)
        }

        // Default body encoding: canonical envelope shape via JSONEncoder
        urlRequest.httpBody = try encodeDefaultBody(for: request)
        return urlRequest
    }

    // MARK: - Body encoding

    private func encodeBody(prepared: PreparedSendRequest, request: TransportSendRequest) throws -> Data {
        let envelope = ChatRequestEnvelope(
            id: prepared.chatId,
            messages: prepared.messages.map { makeEncodableMessage($0) },
            body: prepared.body.isEmpty ? nil : prepared.body,
            metadata: request.options?.metadata.isEmpty == false ? request.options?.metadata : nil
        )
        return try JSONEncoder().encode(envelope)
    }

    private func encodeDefaultBody(for request: TransportSendRequest) throws -> Data {
        let body = request.options?.body
        let metadata = request.options?.metadata
        let envelope = ChatRequestEnvelope(
            id: request.id,
            messages: request.messages.map { makeEncodableMessage($0) },
            body: body?.isEmpty == false ? body : nil,
            metadata: metadata?.isEmpty == false ? metadata : nil
        )
        return try JSONEncoder().encode(envelope)
    }

    private func makeEncodableMessage(_ message: UIMessage) -> EncodableMessage {
        let parts = message.parts.compactMap { makeEncodablePart($0) }
        if parts.isEmpty {
            return EncodableMessage(role: message.role.rawValue, content: message.primaryText, parts: nil)
        }
        return EncodableMessage(role: message.role.rawValue, content: nil, parts: parts)
    }

    private func makeEncodablePart(_ part: UIMessagePart) -> EncodableMessagePart? {
        switch part {
        case .text(let p):
            return .text(p.text)
        case .file(let p):
            return .file(makeEncodableFilePart(p), type: "file")
        case .image(let p):
            return .file(makeEncodableFilePart(p), type: "image")
        default:
            return nil
        }
    }

    private func makeEncodableFilePart(_ p: FilePart) -> EncodableFilePart {
        EncodableFilePart(
            mediaType: p.mediaType,
            name: p.name,
            url: p.url,
            data: p.data,
            fileId: p.fileId
        )
    }
}

/// Errors produced by `HTTPChatTransport`.
public enum TransportError: Error, Sendable {
    case httpError(statusCode: Int)
}
