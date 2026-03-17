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
        let options = ChatRequestOptions(body: ["modelId": .string("gemini-2.0-flash"), "agentId": .string("chat")])
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
            metadata: ["threadId": .string("thread-xyz"), "userId": .string("user-123")]
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
                "modelId": .string("gemini-2.0-flash"),
                "agentId": .string("chat"),
                "runId": .string("run-uuid-here"),
                "maxSteps": .int(5),
            ],
            metadata: [
                "threadId": .string("thread-abc"),
                "userId": .string("user-uuid"),
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
}

// MARK: - FilePart encoding modes

struct FilePartEncodingTests {

    @Test func encodesFilePartWithFileId() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let fp = FilePart.withFileId("file-xyz789", mediaType: "application/pdf", name: "report.pdf")
        let msg = UIMessage(id: "u1", role: .user, parts: [.file(fp)])
        let request = TransportSendRequest(id: "sess-fileid", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let fileParts = parts.filter { $0["type"] as? String == "file" }
        #expect(fileParts.count == 1)
        #expect(fileParts[0]["fileId"] as? String == "file-xyz789")
        #expect(fileParts[0]["mediaType"] as? String == "application/pdf")
        #expect(fileParts[0]["name"] as? String == "report.pdf")
        #expect(fileParts[0]["url"] == nil, "url must be absent when fileId is set")
    }

    @Test func encodesFilePartWithInlineData() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let rawData = Data([0x25, 0x50, 0x44, 0x46]) // %PDF
        let fp = FilePart.withData(rawData, mediaType: "application/pdf", name: "inline.pdf")
        let msg = UIMessage(id: "u1", role: .user, parts: [.file(fp)])
        let request = TransportSendRequest(id: "sess-data", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let fileParts = parts.filter { $0["type"] as? String == "file" }
        #expect(fileParts.count == 1)
        #expect(fileParts[0]["data"] as? String == rawData.base64EncodedString())
        #expect(fileParts[0]["mediaType"] as? String == "application/pdf")
        #expect(fileParts[0]["url"] == nil, "url must be absent when data is set")
        #expect(fileParts[0]["fileId"] == nil, "fileId must be absent when data is set")
    }

    @Test func encodesImagePartWithUrl() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let fp = FilePart(url: "https://example.com/photo.png", mediaType: "image/png", name: "photo.png")
        let msg = UIMessage(id: "u1", role: .user, parts: [.image(fp)])
        let request = TransportSendRequest(id: "sess-image", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let imageParts = parts.filter { $0["type"] as? String == "image" }
        #expect(imageParts.count == 1)
        #expect(imageParts[0]["url"] as? String == "https://example.com/photo.png")
        #expect(imageParts[0]["mediaType"] as? String == "image/png")
        #expect(imageParts[0]["name"] as? String == "photo.png")
    }

    @Test func fileIdTakesPriorityOverDataAndUrl() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        // Manually craft a FilePart with all three fields set — fileId must win
        var fp = FilePart(url: "https://example.com/doc.pdf", mediaType: "application/pdf")
        fp.fileId = "file-priority"
        fp.data = Data([0x01, 0x02])
        let msg = UIMessage(id: "u1", role: .user, parts: [.file(fp)])
        let request = TransportSendRequest(id: "sess-priority", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let fileParts = parts.filter { $0["type"] as? String == "file" }
        #expect(fileParts.count == 1)
        #expect(fileParts[0]["fileId"] as? String == "file-priority")
        #expect(fileParts[0]["data"] == nil, "data must be absent when fileId wins")
        #expect(fileParts[0]["url"] == nil, "url must be absent when fileId wins")
    }

    @Test func dataTakesPriorityOverUrl() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        var fp = FilePart(url: "https://example.com/doc.pdf", mediaType: "application/pdf")
        fp.data = Data([0x01, 0x02])
        let msg = UIMessage(id: "u1", role: .user, parts: [.file(fp)])
        let request = TransportSendRequest(id: "sess-data-priority", messages: [msg])
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = parsed["messages"] as? [[String: Any]],
              let parts = messages[0]["parts"] as? [[String: Any]] else {
            Issue.record("Expected messages with parts"); return
        }

        let fileParts = parts.filter { $0["type"] as? String == "file" }
        #expect(fileParts.count == 1)
        #expect(fileParts[0]["data"] as? String == Data([0x01, 0x02]).base64EncodedString())
        #expect(fileParts[0]["url"] == nil, "url must be absent when data wins")
    }
}

// MARK: - JSONValue body encoding (sb-31j.2)

struct JSONValueBodyEncodingTests {

    @Test func bodyWithNestedJSONValueEncodesWithoutCrash() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let options = ChatRequestOptions(body: [
            "config": .object(["nested": .array([.int(1), .string("two"), .null])]),
            "flag": .bool(true),
        ])
        let request = TransportSendRequest(id: "s1", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        let bodyObj = parsed["body"] as? [String: Any]
        #expect(bodyObj?["flag"] as? Bool == true)
        let config = bodyObj?["config"] as? [String: Any]
        let nested = config?["nested"] as? [Any]
        #expect(nested?.count == 3)
    }

    @Test func metadataWithJSONValueEncodesCorrectly() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let options = ChatRequestOptions(
            metadata: [
                "count": .int(42),
                "enabled": .bool(false),
                "score": .double(3.14),
            ]
        )
        let request = TransportSendRequest(id: "s-meta", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        let metadata = parsed["metadata"] as? [String: Any]
        #expect(metadata?["count"] as? Int == 42)
        #expect(metadata?["enabled"] as? Bool == false)
    }

    @Test func nullJSONValueEncodesInBody() throws {
        let transport = HTTPChatTransport(apiURL: URL(string: "https://api.example.com/chat")!)
        let options = ChatRequestOptions(body: ["nullField": .null])
        let request = TransportSendRequest(id: "s-null", messages: [], options: options)
        let urlReq = try transport.buildURLRequest(for: request)

        guard let bodyData = urlReq.httpBody,
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Expected JSON body"); return
        }

        let bodyObj = parsed["body"] as? [String: Any]
        // NSNull is present for null values
        #expect(bodyObj?["nullField"] is NSNull)
    }
}

// MARK: - requestBuilder override

struct RequestBuilderOverrideTests {

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
                    // Convert [String: JSONValue] → [String: Any] for JSONSerialization
                    envelope["body"] = body.mapValues { $0.rawValue }
                }
                modified.httpBody = try JSONSerialization.data(withJSONObject: envelope)
                return modified
            }
        )

        let options = ChatRequestOptions(body: [
            "modelId": .string("gemini-2.0-flash"),
            "agentId": .string("chat"),
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
