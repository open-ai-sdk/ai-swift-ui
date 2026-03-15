import Testing
import Foundation
@testable import AISwiftUI

// MARK: - HTTPChatTransport request body shape tests (contract §1 compliance)

struct TransportRequestBodyContractTests {

    // MARK: - Envelope shape

    @Test func defaultBodyNestsModelHintsUnderBodyKey() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let options = ChatRequestOptions(body: ["modelId": "gemini-2.0-flash", "agentId": "chat"])
        let request = TransportSendRequest(id: "thread-abc", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        // Contract §1: model hints must be nested under "body", not at the root
        #expect(parsed["modelId"] == nil, "modelId must not appear at root")
        #expect(parsed["agentId"] == nil, "agentId must not appear at root")

        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["modelId"] as? String == "gemini-2.0-flash")
        #expect(bodyObj?["agentId"] as? String == "chat")
    }

    @Test func defaultBodyContainsIdAndMessagesAtRoot() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let userMsg = UIMessage(id: "u1", role: .user, parts: [.text(TextPart(text: "Hello"))])
        let request = TransportSendRequest(id: "sess-root", messages: [userMsg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        #expect(parsed["id"] as? String == "sess-root")
        let messages = parsed["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?[0]["role"] as? String == "user")
    }

    @Test func defaultBodyNestsMetadataUnderMetadataKey() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let options = ChatRequestOptions(
            metadata: ["threadId": "thread-xyz", "userId": "user-123"]
        )
        let request = TransportSendRequest(id: "sess-meta", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        #expect(parsed["threadId"] == nil, "threadId must not appear at root")
        let metadata = parsed["metadata"] as? [String: Any]
        #expect(metadata?["threadId"] as? String == "thread-xyz")
        #expect(metadata?["userId"] as? String == "user-123")
    }

    @Test func defaultBodyWithAllContractFields() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let options = ChatRequestOptions(
            body: [
                "modelId": "gemini-2.0-flash",
                "agentId": "chat",
                "runId": "run-uuid-here",
                "maxSteps": 5,
            ],
            metadata: [
                "threadId": "thread-abc",
                "userId": "user-uuid",
            ]
        )
        let userMsg = UIMessage(id: "u1", role: .user, parts: [.text(TextPart(text: "What is Go?"))])
        let request = TransportSendRequest(id: "thread-abc", messages: [userMsg], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        // Root-level fields
        #expect(parsed["id"] as? String == "thread-abc")
        #expect((parsed["messages"] as? [[String: Any]])?.count == 1)

        // body object
        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["modelId"] as? String == "gemini-2.0-flash")
        #expect(bodyObj?["agentId"] as? String == "chat")
        #expect(bodyObj?["runId"] as? String == "run-uuid-here")
        #expect(bodyObj?["maxSteps"] as? Int == 5)

        // metadata object
        let metadata = parsed["metadata"] as? [String: Any]
        #expect(metadata?["threadId"] as? String == "thread-abc")
        #expect(metadata?["userId"] as? String == "user-uuid")
    }

    @Test func defaultBodyOmitsBodyKeyWhenOptionsBodyIsEmpty() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let request = TransportSendRequest(id: "sess-no-body", messages: [])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        #expect(parsed["body"] == nil)
        #expect(parsed["metadata"] == nil)
    }

    // MARK: - Message encoding

    @Test func encodesUserTextMessageWithPartsArray() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let msg = UIMessage(id: "u1", role: .user, parts: [.text(TextPart(text: "Explain Go"))])
        let request = TransportSendRequest(id: "sess-parts", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "Explain Go")
    }

    @Test func encodesAssistantMessageWithContentFallbackWhenNoEncodableParts() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        // Assistant message with only a text part (not file, not image) — should use parts
        let textPart = TextPart(text: "Go is a statically typed language.")
        let msg = UIMessage(id: "a1", role: .assistant, parts: [.text(textPart)])
        let request = TransportSendRequest(id: "sess-assistant", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]] else {
            Issue.record("Expected messages array"); return
        }

        #expect(messages[0]["role"] as? String == "assistant")
        // text part encodes into parts array
        let parts = messages[0]["parts"] as? [[String: Any]]
        #expect(parts?.count == 1)
        #expect(parts?[0]["text"] as? String == "Go is a statically typed language.")
    }

    @Test func encodesFilePartWithRequiredFields() throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!
        )
        let filePart = FilePart(url: "data:application/pdf;base64,abc", mediaType: "application/pdf", name: "notes.pdf")
        let msg = UIMessage(id: "u1", role: .user, parts: [
            .text(TextPart(text: "See attached")),
            .file(filePart),
        ])
        let request = TransportSendRequest(id: "sess-file", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let fileParts = parts.filter { $0["type"] as? String == "file" }
        #expect(fileParts.count == 1)
        #expect(fileParts[0]["url"] as? String == "data:application/pdf;base64,abc")
        #expect(fileParts[0]["mediaType"] as? String == "application/pdf")
        #expect(fileParts[0]["name"] as? String == "notes.pdf")
    }

    // MARK: - requestBuilder override

    @Test func requestBuilderCanProduceSecondBrainStyleEnvelope() throws {
        // Simulates how second-brain-app would override the request to add attachments
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://api.example.com/chat")!,
            requestBuilder: { req, urlReq in
                var modified = urlReq
                var envelope: [String: Any] = [
                    "id": req.id,
                    "messages": req.messages.map { ["role": $0.role.rawValue, "content": $0.primaryText] },
                ]
                if let body = req.options?.body, !body.isEmpty {
                    envelope["body"] = body
                }
                // Attach second-brain-style attachments from body extras
                if let attachments = req.options?.body["attachments"] {
                    var bodyObj = envelope["body"] as? [String: Any] ?? [:]
                    bodyObj["attachments"] = attachments
                    envelope["body"] = bodyObj
                }
                modified.httpBody = try JSONSerialization.data(withJSONObject: envelope)
                return modified
            }
        )

        let options = ChatRequestOptions(body: [
            "modelId": "gemini-2.0-flash",
            "agentId": "chat",
        ])
        let request = TransportSendRequest(
            id: "thread-second-brain",
            messages: [UIMessage(id: "u1", role: .user, parts: [.text(TextPart(text: "Hello"))])],
            options: options
        )
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        #expect(parsed["id"] as? String == "thread-second-brain")
        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["modelId"] as? String == "gemini-2.0-flash")
    }
}
