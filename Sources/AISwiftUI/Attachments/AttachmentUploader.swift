import Foundation

/// Protocol for uploading pending attachments to a backend storage service.
/// Apps implement this to integrate with their presign/upload flow.
public protocol AttachmentUploader: Sendable {
    func upload(_ attachment: PendingAttachment) async throws -> FilePart
}
