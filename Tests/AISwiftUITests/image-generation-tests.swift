import Testing
import Foundation
@testable import AISwiftUI

// MARK: - FilePart image convenience tests

struct FilePartImageTests {

    // MARK: - isImage

    @Test func isImage_withImagePng_returnsTrue() {
        let fp = FilePart(url: "", mediaType: "image/png")
        #expect(fp.isImage)
    }

    @Test func isImage_withImageJpeg_returnsTrue() {
        let fp = FilePart(url: "", mediaType: "image/jpeg")
        #expect(fp.isImage)
    }

    @Test func isImage_withImageWebp_returnsTrue() {
        let fp = FilePart(url: "", mediaType: "image/webp")
        #expect(fp.isImage)
    }

    @Test func isImage_withApplicationPdf_returnsFalse() {
        let fp = FilePart(url: "", mediaType: "application/pdf")
        #expect(!fp.isImage)
    }

    @Test func isImage_withTextPlain_returnsFalse() {
        let fp = FilePart(url: "", mediaType: "text/plain")
        #expect(!fp.isImage)
    }

    // MARK: - imageData

    @Test func imageData_withInlineData_returnsData() {
        let raw = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let fp = FilePart.withData(raw, mediaType: "image/png")
        #expect(fp.imageData == raw)
    }

    @Test func imageData_withDataURL_decodesBase64() {
        let original = Data([0x89, 0x50, 0x4E, 0x47])
        let base64 = original.base64EncodedString()
        let fp = FilePart(url: "data:image/png;base64,\(base64)", mediaType: "image/png")
        #expect(fp.imageData == original)
    }

    @Test func imageData_withRegularURL_returnsNil() {
        let fp = FilePart(url: "https://example.com/img.png", mediaType: "image/png")
        #expect(fp.imageData == nil)
    }

    @Test func imageData_withEmptyURL_returnsNil() {
        let fp = FilePart(url: "", mediaType: "image/png")
        #expect(fp.imageData == nil)
    }

    // MARK: - thoughtSignature

    @Test func thoughtSignature_codableRoundTrip() throws {
        var fp = FilePart(url: "data:image/png;base64,abc", mediaType: "image/png")
        fp.thoughtSignature = "sig-xyz-123"
        let data = try JSONEncoder().encode(fp)
        let decoded = try JSONDecoder().decode(FilePart.self, from: data)
        #expect(decoded.thoughtSignature == "sig-xyz-123")
        #expect(decoded == fp)
    }

    @Test func thoughtSignature_nilByDefault() {
        let fp = FilePart(url: "", mediaType: "image/png")
        #expect(fp.thoughtSignature == nil)
    }

    @Test func thoughtSignature_decodesFromLegacyJSON() throws {
        let json = #"{"url":"https://example.com/img.png","mediaType":"image/png"}"#
        let decoded = try JSONDecoder().decode(FilePart.self, from: json.data(using: .utf8)!)
        #expect(decoded.thoughtSignature == nil)
        #expect(decoded.url == "https://example.com/img.png")
    }
}

// MARK: - UIMessageChunkDecoder image tests

struct ImageChunkDecoderTests {

    let decoder = UIMessageChunkDecoder()

    @Test func decodesImageChunk() throws {
        let json = #"data: {"type":"image","url":"data:image/png;base64,abc","mediaType":"image/png"}"#
        let chunk = try decoder.decode(json)
        guard case .image(let url, let mediaType, let sig) = chunk else {
            Issue.record("Expected .image chunk"); return
        }
        #expect(url == "data:image/png;base64,abc")
        #expect(mediaType == "image/png")
        #expect(sig == nil)
    }

    @Test func decodesImageChunkWithThoughtSignature() throws {
        let json = #"data: {"type":"image","url":"data:image/png;base64,abc","mediaType":"image/png","thoughtSignature":"sig-D"}"#
        let chunk = try decoder.decode(json)
        guard case .image(let url, let mediaType, let sig) = chunk else {
            Issue.record("Expected .image chunk"); return
        }
        #expect(url == "data:image/png;base64,abc")
        #expect(mediaType == "image/png")
        #expect(sig == "sig-D")
    }

    @Test func decodesImageChunkMissingOptionalFields() throws {
        let json = #"data: {"type":"image"}"#
        let chunk = try decoder.decode(json)
        guard case .image(let url, let mediaType, let sig) = chunk else {
            Issue.record("Expected .image chunk"); return
        }
        #expect(url == "")
        #expect(mediaType == "")
        #expect(sig == nil)
    }
}

// MARK: - UIMessageStreamReducer image tests

struct ImageReducerTests {

    @Test func imageChunk_appendsImagePart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-img")
        reducer.apply(.image(url: "data:image/png;base64,abc", mediaType: "image/png"))

        #expect(reducer.message.parts.count == 1)
        if case .image(let fp) = reducer.message.parts[0] {
            #expect(fp.url == "data:image/png;base64,abc")
            #expect(fp.mediaType == "image/png")
        } else {
            Issue.record("Expected .image part")
        }
    }

    @Test func imageChunkWithThoughtSignature_preservesSignature() {
        var reducer = UIMessageStreamReducer(messageId: "msg-img-sig")
        reducer.apply(.image(
            url: "data:image/png;base64,abc",
            mediaType: "image/png",
            thoughtSignature: "sig-E"
        ))

        #expect(reducer.message.parts.count == 1)
        if case .image(let fp) = reducer.message.parts[0] {
            #expect(fp.thoughtSignature == "sig-E")
        } else {
            Issue.record("Expected .image part")
        }
    }

    @Test func fileChunkWithImageMediaType_routesToImagePart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-file-img")
        reducer.apply(.file(url: "data:image/jpeg;base64,xyz", mediaType: "image/jpeg"))

        #expect(reducer.message.parts.count == 1)
        if case .image(let fp) = reducer.message.parts[0] {
            #expect(fp.url == "data:image/jpeg;base64,xyz")
            #expect(fp.mediaType == "image/jpeg")
        } else {
            Issue.record("Expected .image part (auto-routed from file chunk)")
        }
    }

    @Test func fileChunkWithNonImageMediaType_routesToFilePart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-file-pdf")
        reducer.apply(.file(url: "https://example.com/doc.pdf", mediaType: "application/pdf"))

        #expect(reducer.message.parts.count == 1)
        if case .file(let fp) = reducer.message.parts[0] {
            #expect(fp.url == "https://example.com/doc.pdf")
            #expect(fp.mediaType == "application/pdf")
        } else {
            Issue.record("Expected .file part")
        }
    }

    @Test func mixedTextAndImage_preservesOrder() {
        var reducer = UIMessageStreamReducer(messageId: "msg-mixed")
        reducer.apply(.textStart(id: "t1"))
        reducer.apply(.textDelta(id: "t1", delta: "Here is the image:"))
        reducer.apply(.textEnd(id: "t1"))
        reducer.apply(.image(url: "data:image/png;base64,abc", mediaType: "image/png"))

        let parts = reducer.message.parts
        #expect(parts.count == 2)
        if case .text(let tp) = parts[0] {
            #expect(tp.text == "Here is the image:")
        } else {
            Issue.record("Expected text part at index 0")
        }
        if case .image(let fp) = parts[1] {
            #expect(fp.mediaType == "image/png")
        } else {
            Issue.record("Expected image part at index 1")
        }
    }
}

// MARK: - UIMessage image accessor tests

struct UIMessageImageAccessorTests {

    @Test func images_returnsOnlyImageParts() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "Hello")),
            .image(FilePart(url: "img1.png", mediaType: "image/png")),
            .file(FilePart(url: "doc.pdf", mediaType: "application/pdf")),
            .image(FilePart(url: "img2.jpg", mediaType: "image/jpeg")),
        ])
        #expect(msg.images.count == 2)
        #expect(msg.images[0].url == "img1.png")
        #expect(msg.images[1].url == "img2.jpg")
    }

    @Test func hasImages_trueWhenImagesExist() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "Hello")),
            .image(FilePart(url: "img.png", mediaType: "image/png")),
        ])
        #expect(msg.hasImages)
    }

    @Test func hasImages_falseWhenNoImages() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "Hello")),
            .file(FilePart(url: "doc.pdf", mediaType: "application/pdf")),
        ])
        #expect(!msg.hasImages)
    }

    @Test func allFiles_returnsBothFilesAndImages() {
        let msg = UIMessage(id: "x", role: .assistant, parts: [
            .file(FilePart(url: "doc.pdf", mediaType: "application/pdf")),
            .image(FilePart(url: "img.png", mediaType: "image/png")),
            .text(TextPart(text: "text")),
        ])
        #expect(msg.allFiles.count == 2)
        #expect(msg.allFiles[0].url == "doc.pdf")
        #expect(msg.allFiles[1].url == "img.png")
    }

    @Test func firstImage_returnsFirstOrNil() {
        let withImage = UIMessage(id: "x", role: .assistant, parts: [
            .text(TextPart(text: "text")),
            .image(FilePart(url: "img.png", mediaType: "image/png")),
        ])
        #expect(withImage.firstImage?.url == "img.png")

        let withoutImage = UIMessage(id: "y", role: .assistant, parts: [
            .text(TextPart(text: "text")),
        ])
        #expect(withoutImage.firstImage == nil)
    }
}
