import Testing
import Foundation
@testable import AISwiftUI

// MARK: - MockChatTransport

/// A deterministic mock transport that replays a fixed chunk sequence.
struct MockChatTransport: ChatTransport, Sendable {
    let chunks: [UIMessageChunk]
    let errorToThrow: (any Error)?

    init(chunks: [UIMessageChunk], error: (any Error)? = nil) {
        self.chunks = chunks
        self.errorToThrow = error
    }

    func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error> {
        let chunks = self.chunks
        let error = self.errorToThrow
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

// MARK: - Helpers

private func fixtureSSE(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
        throw FixtureMissing(name: name)
    }
    return try Data(contentsOf: url)
}

private struct FixtureMissing: Error { let name: String }

// MARK: - HTTPChatTransport request-building unit tests

struct HTTPTransportRequestBuildingTests {

    @Test func defaultHeadersAreIncluded() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            headers: { ["Authorization": "Bearer token123"] }
        )
        let request = TransportSendRequest(id: "sess-1", messages: [])
        let urlReq = try transport.buildURLRequest(for: request)

        #expect(urlReq.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlReq.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
        #expect(urlReq.httpMethod == "POST")
    }

    @Test func perRequestHeadersAreMerged() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!
        )
        let options = ChatRequestOptions(headers: ["X-Thread": "thread-99"])
        let request = TransportSendRequest(id: "sess-2", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        #expect(urlReq.value(forHTTPHeaderField: "X-Thread") == "thread-99")
    }

    @Test func customRequestBuilderIsUsed() throws {
        nonisolated(unsafe) var builderCalled = false
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            requestBuilder: { req, urlReq in
                builderCalled = true
                var modified = urlReq
                modified.setValue("custom-app/1.0", forHTTPHeaderField: "User-Agent")
                modified.httpBody = try JSONSerialization.data(withJSONObject: ["id": req.id])
                return modified
            }
        )
        let request = TransportSendRequest(id: "sess-custom", messages: [])
        let urlReq = try transport.buildURLRequest(for: request)

        #expect(builderCalled)
        #expect(urlReq.value(forHTTPHeaderField: "User-Agent") == "custom-app/1.0")
        // Verify body contains the id
        if let body = urlReq.httpBody,
           let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: String] {
            #expect(parsed["id"] == "sess-custom")
        } else {
            Issue.record("Expected JSON body with id field")
        }
    }

    @Test func defaultBodyContainsSessionId() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!
        )
        let request = TransportSendRequest(id: "session-abc", messages: [])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let body = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Expected JSON body")
            return
        }
        #expect(parsed["id"] as? String == "session-abc")
    }

    @Test func optionsBodyAndMetadataAreMerged() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!
        )
        let options = ChatRequestOptions(
            body: ["modelId": .string("gpt-4o")],
            metadata: ["threadId": .string("thread-123")]
        )
        let request = TransportSendRequest(id: "sess-merge", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let body = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Expected JSON body")
            return
        }
        // Contract §1: model hints are nested under "body", not at the root
        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["modelId"] as? String == "gpt-4o")
        let metadata = parsed["metadata"] as? [String: Any]
        #expect(metadata?["threadId"] as? String == "thread-123")
    }
}

// MARK: - prepareSendRequest hook tests (sb-31j.3)

struct PrepareSendRequestHookTests {

    @Test func hookCanModifyBody() async throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            prepareSendRequest: { prepared in
                var p = prepared
                p.body["injected"] = .string("by-hook")
                return p
            }
        )
        let request = TransportSendRequest(id: "s1", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        guard let body = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }
        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["injected"] as? String == "by-hook")
    }

    @Test func hookCanFilterMessages() async throws {
        let messages = [
            UIMessage(id: "u1", role: .user, parts: [.text(TextPart(text: "Old"))]),
            UIMessage(id: "a1", role: .assistant, parts: [.text(TextPart(text: "Old answer"))]),
            UIMessage(id: "u2", role: .user, parts: [.text(TextPart(text: "New"))]),
        ]
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            prepareSendRequest: { prepared in
                var p = prepared
                // Keep only the last message
                p.messages = Array(prepared.messages.suffix(1))
                return p
            }
        )
        let request = TransportSendRequest(id: "s2", messages: messages)
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        guard let body = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }
        let sentMessages = parsed["messages"] as? [[String: Any]]
        #expect(sentMessages?.count == 1)
        #expect(sentMessages?[0]["role"] as? String == "user")
    }

    @Test func hookCanChangeURL() async throws {
        let alternateURL = URL(string: "https://other.example.com/v2/chat")!
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            prepareSendRequest: { prepared in
                var p = prepared
                p.api = alternateURL
                return p
            }
        )
        let request = TransportSendRequest(id: "s3", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        #expect(urlReq.url == alternateURL)
    }

    @Test func hookAndRequestBuilderCompose() async throws {
        // Hook sets body value; requestBuilder adds custom header — both must appear in final request
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            prepareSendRequest: { prepared in
                var p = prepared
                p.body["fromHook"] = .string("yes")
                return p
            },
            requestBuilder: { req, urlReq in
                var modified = urlReq
                modified.setValue("builder-value", forHTTPHeaderField: "X-From-Builder")
                // Re-encode body including hook changes via options.body
                var envelope: [String: Any] = ["id": req.id, "messages": []]
                if let body = req.options?.body, !body.isEmpty {
                    envelope["body"] = body.mapValues { $0.rawValue }
                }
                modified.httpBody = try JSONSerialization.data(withJSONObject: envelope)
                return modified
            }
        )
        let options = ChatRequestOptions(body: ["fromHook": .string("yes")])
        let request = TransportSendRequest(id: "s4", messages: [], options: options)
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        #expect(urlReq.value(forHTTPHeaderField: "X-From-Builder") == "builder-value")
        if let body = urlReq.httpBody,
           let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let bodyObj = parsed["body"] as? [String: Any]
            #expect(bodyObj?["fromHook"] as? String == "yes")
        } else {
            Issue.record("Expected JSON body with fromHook")
        }
    }
}

// MARK: - MockChatTransport tests

struct MockTransportTests {

    @Test func mockTransportYieldsChunks() async throws {
        let transport = MockChatTransport(chunks: [
            .start(messageId: "msg-1"),
            .startStep,
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "Hello"),
            .textEnd(id: "t1"),
            .finishStep,
            .finish(),
        ])

        var reducer = UIMessageStreamReducer(messageId: "msg-1")
        let request = TransportSendRequest(id: "s1", messages: [])
        for try await chunk in transport.send(request) {
            reducer.apply(chunk)
        }

        #expect(reducer.message.primaryText == "Hello")
        #expect(reducer.isFinished)
    }

    @Test func mockTransportThrowsError() async throws {
        struct TestError: Error {}
        let transport = MockChatTransport(chunks: [.start(messageId: "msg-e")], error: TestError())

        var didThrow = false
        let request = TransportSendRequest(id: "s2", messages: [])
        do {
            for try await _ in transport.send(request) {}
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test func mockTransportReturnsAllChunkTypes() async throws {
        let chunks: [UIMessageChunk] = [
            .start(messageId: "msg-all"),
            .startStep,
            .reasoningStart(id: "r1"),
            .reasoningDelta(id: "r1", delta: "thinking"),
            .reasoningEnd(id: "r1", signature: nil),
            .toolInputStart(toolCallId: "tc1", toolName: "search"),
            .toolInputDelta(toolCallId: "tc1", inputTextDelta: "{"),
            .toolInputAvailable(toolCallId: "tc1", toolName: "search", input: .object(["q": .string("go")])),
            .toolOutputAvailable(toolCallId: "tc1", output: .object(["results": .array([])])),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "Found results"),
            .textEnd(id: "t1"),
            .sources([SourceURLPart(url: "https://go.dev", title: "Go")]),
            .data(name: "plan", payload: .object(["step": .string("done")])),
            .finishStep,
            .finish(),
        ]

        let transport = MockChatTransport(chunks: chunks)
        var reducer = UIMessageStreamReducer(messageId: "msg-all")
        for try await chunk in transport.send(TransportSendRequest(id: "s3", messages: [])) {
            reducer.apply(chunk)
        }

        #expect(reducer.isFinished)
        #expect(reducer.message.primaryText == "Found results")
        #expect(reducer.message.toolInvocations.count == 1)
        #expect(reducer.message.sources.count == 1)
        #expect(reducer.message.dataParts.count == 1)
    }
}
