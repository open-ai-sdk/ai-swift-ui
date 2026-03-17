import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Mock Uploader

private struct MockAttachmentUploader: AttachmentUploader {
    nonisolated(unsafe) var uploadedAttachments: [PendingAttachment] = []
    let returnFileId: String

    func upload(_ attachment: PendingAttachment) async throws -> FilePart {
        .withFileId(returnFileId, mediaType: attachment.mimeType, name: attachment.filename)
    }
}

private struct FailingAttachmentUploader: AttachmentUploader {
    struct UploadError: Error {}
    func upload(_ attachment: PendingAttachment) async throws -> FilePart {
        throw UploadError()
    }
}

// MARK: - PendingAttachment Tests

struct PendingAttachmentModelTests {

    @Test func pendingAttachmentCreationFields() {
        let data = Data("test".utf8)
        let attachment = PendingAttachment(id: "att-1", data: data, filename: "file.txt", mimeType: "text/plain")
        #expect(attachment.id == "att-1")
        #expect(attachment.data == data)
        #expect(attachment.filename == "file.txt")
        #expect(attachment.mimeType == "text/plain")
    }

    @Test func pendingAttachmentAutoGeneratesId() {
        let a1 = PendingAttachment(data: Data(), filename: "a.jpg", mimeType: "image/jpeg")
        let a2 = PendingAttachment(data: Data(), filename: "b.jpg", mimeType: "image/jpeg")
        #expect(a1.id != a2.id)
        #expect(!a1.id.isEmpty)
    }

    @Test func pendingAttachmentEquatable() {
        let data = Data("hello".utf8)
        let a1 = PendingAttachment(id: "same-id", data: data, filename: "f.txt", mimeType: "text/plain")
        let a2 = PendingAttachment(id: "same-id", data: data, filename: "f.txt", mimeType: "text/plain")
        let a3 = PendingAttachment(id: "diff-id", data: data, filename: "f.txt", mimeType: "text/plain")
        #expect(a1 == a2)
        #expect(a1 != a3)
    }
}

// MARK: - Attachment Management on ChatSession

@MainActor
struct AttachmentUploadTests {

    @Test func addAttachmentAppendsToSession() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "s-att-1", transport: transport)

        session.addAttachment(data: Data("img".utf8), filename: "photo.jpg", mimeType: "image/jpeg")

        #expect(session.pendingAttachments.count == 1)
        #expect(session.pendingAttachments[0].filename == "photo.jpg")
        #expect(session.pendingAttachments[0].mimeType == "image/jpeg")
    }

    @Test func removeAttachmentByIdRemovesCorrectOne() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "s-att-2", transport: transport)

        session.addAttachment(data: Data("a".utf8), filename: "a.txt", mimeType: "text/plain")
        session.addAttachment(data: Data("b".utf8), filename: "b.txt", mimeType: "text/plain")
        #expect(session.pendingAttachments.count == 2)

        let idToRemove = session.pendingAttachments[0].id
        session.removeAttachment(id: idToRemove)

        #expect(session.pendingAttachments.count == 1)
        #expect(session.pendingAttachments[0].filename == "b.txt")
    }

    @Test func clearAttachmentsRemovesAll() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "s-att-3", transport: transport)

        session.addAttachment(data: Data("1".utf8), filename: "1.txt", mimeType: "text/plain")
        session.addAttachment(data: Data("2".utf8), filename: "2.txt", mimeType: "text/plain")
        session.addAttachment(data: Data("3".utf8), filename: "3.txt", mimeType: "text/plain")
        #expect(session.pendingAttachments.count == 3)

        session.clearAttachments()
        #expect(session.pendingAttachments.isEmpty)
    }

    @Test func removeNonExistentIdIsNoop() {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "s-att-4", transport: transport)

        session.addAttachment(data: Data("x".utf8), filename: "x.txt", mimeType: "text/plain")
        session.removeAttachment(id: "does-not-exist")

        #expect(session.pendingAttachments.count == 1)
    }

    @Test func sendClearsAttachmentsAfterUpload() async throws {
        let chunks: [UIMessageChunk] = [
            .start(messageId: "msg-att"),
            .startStep,
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "Got your file"),
            .textEnd(id: "t1"),
            .finishStep,
            .finish(),
        ]
        let transport = MockChatTransport(chunks: chunks)
        let session = ChatSession(id: "s-att-5", transport: transport)
        session.attachmentUploader = MockAttachmentUploader(returnFileId: "file-123")

        session.addAttachment(data: Data("doc".utf8), filename: "doc.pdf", mimeType: "application/pdf")
        #expect(session.pendingAttachments.count == 1)

        await session.send(.user(text: "Here is my file"))

        // Attachments cleared after send
        #expect(session.pendingAttachments.isEmpty)
        #expect(session.status == .ready)
    }

    @Test func sendWithFailingUploaderSetsError() async throws {
        let transport = MockChatTransport(chunks: [])
        let session = ChatSession(id: "s-att-6", transport: transport)
        session.attachmentUploader = FailingAttachmentUploader()

        session.addAttachment(data: Data("data".utf8), filename: "file.bin", mimeType: "application/octet-stream")

        await session.send(.user(text: "upload this"))

        #expect(session.status == .error)
        #expect(session.error != nil)
    }
}
