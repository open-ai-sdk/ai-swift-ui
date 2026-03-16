import Foundation

/// A `ChatTransport` implementation that sends requests over HTTP/SSE using `URLSession`.
///
/// The transport is configurable via:
/// - `apiURL`: the endpoint to POST to
/// - `headers`: a closure returning static or dynamic headers (e.g. auth tokens)
/// - `requestBuilder`: optional closure to fully customize the `URLRequest` before sending
///
/// By default the transport encodes the request body as the canonical
/// `ChatRequestEnvelope`-shaped JSON. Supply a `requestBuilder` to reshape
/// the body for app-specific backends.
public final class HTTPChatTransport: ChatTransport, @unchecked Sendable {

    /// The API endpoint URL.
    public let apiURL: URL

    /// Returns headers to attach to every request (e.g. Authorization).
    public var headers: @Sendable () -> [String: String]

    /// Optional hook to fully customize the `URLRequest` before it is sent.
    /// Return the modified request. Returning `nil` uses the default encoding.
    public var requestBuilder: (@Sendable (TransportSendRequest, URLRequest) throws -> URLRequest)?

    private let session: URLSession
    private let decoder = UIMessageChunkDecoder()

    public init(
        apiURL: URL,
        headers: @escaping @Sendable () -> [String: String] = { [:] },
        requestBuilder: (@Sendable (TransportSendRequest, URLRequest) throws -> URLRequest)? = nil,
        session: URLSession = .shared
    ) {
        self.apiURL = apiURL
        self.headers = headers
        self.requestBuilder = requestBuilder
        self.session = session
    }

    public func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try self.buildURLRequest(for: request)
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

        // Default body encoding: canonical envelope shape
        urlRequest.httpBody = try encodeDefaultBody(for: request)
        return urlRequest
    }

    private func encodeDefaultBody(for request: TransportSendRequest) throws -> Data {
        var envelope: [String: Any] = [
            "id": request.id,
            "messages": request.messages.map { encodeMessage($0) },
        ]
        // Contract §1: model/route hints go under the "body" key, not at the root.
        if let bodyExtra = request.options?.body, !bodyExtra.isEmpty {
            envelope["body"] = bodyExtra
        }
        if let metadata = request.options?.metadata, !metadata.isEmpty {
            envelope["metadata"] = metadata
        }
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func encodeMessage(_ message: UIMessage) -> [String: Any] {
        var result: [String: Any] = ["role": message.role.rawValue]
        let parts = message.parts.compactMap { encodePart($0) }
        if parts.isEmpty {
            result["content"] = message.primaryText
        } else {
            result["parts"] = parts
        }
        return result
    }

    private func encodePart(_ part: UIMessagePart) -> [String: Any]? {
        switch part {
        case .text(let p):
            return ["type": "text", "text": p.text]
        case .file(let p):
            return encodeFilePart(p, type: "file")
        case .image(let p):
            return encodeFilePart(p, type: "image")
        default:
            return nil
        }
    }

    private func encodeFilePart(_ p: FilePart, type: String) -> [String: Any] {
        var d: [String: Any] = ["type": type, "mediaType": p.mediaType]
        if let name = p.name { d["name"] = name }
        // Priority: fileId > data > url
        if let fileId = p.fileId, !fileId.isEmpty {
            d["fileId"] = fileId
        } else if let data = p.data, !data.isEmpty {
            d["data"] = data.base64EncodedString()
        } else if !p.url.isEmpty {
            d["url"] = p.url
        }
        return d
    }
}

/// Errors produced by `HTTPChatTransport`.
public enum TransportError: Error, Sendable {
    case httpError(statusCode: Int)
}
