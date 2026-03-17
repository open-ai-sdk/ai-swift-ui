import Testing
import Foundation
@testable import AISwiftUI

// MARK: - New chunk type decoding tests

struct NewChunkTypeDecodingTests {

    let decoder = UIMessageChunkDecoder()

    // MARK: - message-metadata

    @Test func decodesMessageMetadataChunk() throws {
        let json = #"data: {"type":"message-metadata","messageMetadata":{"model":"gpt-4o","version":"2025-01"}}"#
        let chunk = try decoder.decode(json)
        guard case .messageMetadata(let metadata) = chunk else {
            Issue.record("Expected .messageMetadata"); return
        }
        #expect(metadata["model"]?.stringValue == "gpt-4o")
        #expect(metadata["version"]?.stringValue == "2025-01")
    }

    @Test func decodesMessageMetadataChunkEmptyPayload() throws {
        let json = #"data: {"type":"message-metadata","messageMetadata":{}}"#
        let chunk = try decoder.decode(json)
        guard case .messageMetadata(let metadata) = chunk else {
            Issue.record("Expected .messageMetadata"); return
        }
        #expect(metadata.isEmpty)
    }

    @Test func decodesStartChunkWithMessageMetadata() throws {
        let json = #"data: {"type":"start","messageId":"msg-start","messageMetadata":{"createdAt":123,"model":"gemini-2.5-flash"}}"#
        let chunk = try decoder.decode(json)
        guard case .start(let messageId, let metadata) = chunk else {
            Issue.record("Expected .start"); return
        }
        #expect(messageId == "msg-start")
        #expect(metadata?["createdAt"]?.intValue == 123)
        #expect(metadata?["model"]?.stringValue == "gemini-2.5-flash")
    }

    // MARK: - abort

    @Test func decodesAbortChunkWithReason() throws {
        let json = #"data: {"type":"abort","reason":"rate limit exceeded"}"#
        let chunk = try decoder.decode(json)
        guard case .abort(let reason) = chunk else {
            Issue.record("Expected .abort"); return
        }
        #expect(reason == "rate limit exceeded")
    }

    @Test func decodesAbortChunkWithoutReason() throws {
        let json = #"data: {"type":"abort"}"#
        let chunk = try decoder.decode(json)
        guard case .abort(let reason) = chunk else {
            Issue.record("Expected .abort"); return
        }
        #expect(reason == nil)
    }

    // MARK: - source-url

    @Test func decodesSourceURLChunk() throws {
        let json = #"data: {"type":"source-url","sourceId":"src-abc","url":"https://example.com","title":"Example Page"}"#
        let chunk = try decoder.decode(json)
        guard case .sourceURL(let sourceId, let url, let title) = chunk else {
            Issue.record("Expected .sourceURL"); return
        }
        #expect(sourceId == "src-abc")
        #expect(url == "https://example.com")
        #expect(title == "Example Page")
    }

    @Test func decodesSourceURLChunkWithoutTitle() throws {
        let json = #"data: {"type":"source-url","sourceId":"src-abc","url":"https://example.com"}"#
        let chunk = try decoder.decode(json)
        guard case .sourceURL(let sourceId, let url, let title) = chunk else {
            Issue.record("Expected .sourceURL"); return
        }
        #expect(sourceId == "src-abc")
        #expect(url == "https://example.com")
        #expect(title == nil)
    }

    // MARK: - source-document

    @Test func decodesSourceDocumentChunk() throws {
        let json = """
            data: {"type":"source-document","sourceId":"doc-1",\
            "mediaType":"application/pdf","title":"Research Paper","filename":"paper.pdf"}
            """
        let chunk = try decoder.decode(json)
        guard case .sourceDocument(let sourceId, let mediaType, let title, let filename) = chunk else {
            Issue.record("Expected .sourceDocument"); return
        }
        #expect(sourceId == "doc-1")
        #expect(mediaType == "application/pdf")
        #expect(title == "Research Paper")
        #expect(filename == "paper.pdf")
    }

    // MARK: - file

    @Test func decodesFileChunk() throws {
        let json = #"data: {"type":"file","url":"https://files.example.com/doc.pdf","mediaType":"application/pdf"}"#
        let chunk = try decoder.decode(json)
        guard case .file(let url, let mediaType) = chunk else {
            Issue.record("Expected .file"); return
        }
        #expect(url == "https://files.example.com/doc.pdf")
        #expect(mediaType == "application/pdf")
    }

    // MARK: - finish with finishReason

    @Test func decodesFinishChunkWithFinishReason() throws {
        let json = #"data: {"type":"finish","finishReason":"stop"}"#
        let chunk = try decoder.decode(json)
        guard case .finish(let reason, let metadata) = chunk else {
            Issue.record("Expected .finish"); return
        }
        #expect(reason == "stop")
        #expect(metadata == nil)
    }

    @Test func decodesFinishChunkWithoutFinishReason() throws {
        let json = #"data: {"type":"finish"}"#
        let chunk = try decoder.decode(json)
        guard case .finish(let reason, let metadata) = chunk else {
            Issue.record("Expected .finish"); return
        }
        #expect(reason == nil)
        #expect(metadata == nil)
    }

    @Test func decodesFinishChunkWithMessageMetadata() throws {
        let json = #"data: {"type":"finish","finishReason":"stop","messageMetadata":{"totalTokens":321}}"#
        let chunk = try decoder.decode(json)
        guard case .finish(let reason, let metadata) = chunk else {
            Issue.record("Expected .finish"); return
        }
        #expect(reason == "stop")
        #expect(metadata?["totalTokens"]?.intValue == 321)
    }

    // MARK: - data-* with transient and id

    @Test func decodesDataChunkWithTransientTrue() throws {
        let json = #"data: {"type":"data-plan","data":{"text":"step 1"},"transient":true,"id":"plan-001"}"#
        let chunk = try decoder.decode(json)
        guard case .data(let name, _, let isTransient, let dataId) = chunk else {
            Issue.record("Expected .data"); return
        }
        #expect(name == "plan")
        #expect(isTransient == true)
        #expect(dataId == "plan-001")
    }

    @Test func decodesDataChunkTransientDefaultsFalse() throws {
        let json = #"data: {"type":"data-plan","data":{"text":"step 1"}}"#
        let chunk = try decoder.decode(json)
        guard case .data(_, _, let isTransient, let dataId) = chunk else {
            Issue.record("Expected .data"); return
        }
        #expect(isTransient == false)
        #expect(dataId == nil)
    }
}

// MARK: - Reducer new chunk handling tests

struct ReducerNewChunkTests {

    // MARK: - messageMetadata → message.metadata

    @Test func reducerAttachesMetadataToMessage() {
        var reducer = UIMessageStreamReducer(messageId: "msg-meta")
        reducer.apply(.start(messageId: "msg-meta"))
        reducer.apply(.messageMetadata(metadata: ["model": .string("gpt-4o"), "tokens": .int(500)]))
        reducer.apply(.finish())

        #expect(reducer.message.metadata?["model"]?.stringValue == "gpt-4o")
        #expect(reducer.message.metadata?["tokens"]?.intValue == 500)
        #expect(reducer.isFinished)
    }

    @Test func reducerMergesMetadataAcrossStartAndFinish() {
        var reducer = UIMessageStreamReducer(messageId: "msg-meta-merge")
        reducer.apply(.start(messageId: "msg-meta-merge", metadata: ["model": .string("gemini-2.5-flash")]))
        reducer.apply(.finish(finishReason: "stop", metadata: ["totalTokens": .int(222)]))

        #expect(reducer.message.metadata?["model"]?.stringValue == "gemini-2.5-flash")
        #expect(reducer.message.metadata?["totalTokens"]?.intValue == 222)
    }

    // MARK: - abort → isAborted

    @Test func reducerSetsIsAbortedOnAbortChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-abort")
        reducer.apply(.start(messageId: "msg-abort"))
        reducer.apply(.abort(reason: "server overload"))

        #expect(reducer.isAborted == true)
        #expect(reducer.error == "server overload")
    }

    @Test func reducerSetsIsAbortedWithoutReason() {
        var reducer = UIMessageStreamReducer(messageId: "msg-abort2")
        reducer.apply(.abort(reason: nil))

        #expect(reducer.isAborted == true)
        #expect(reducer.error == "aborted")
    }

    // MARK: - sourceURL chunk → .sourceURL part

    @Test func reducerAppendsSourceURLPartFromSourceURLChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-srcurl")
        reducer.apply(.sourceURL(sourceId: "src-1", url: "https://example.com", title: "Example"))

        let sources = reducer.message.sources
        #expect(sources.count == 1)
        if case .sourceURL(let part) = sources[0] {
            #expect(part.id == "src-1")
            #expect(part.url == "https://example.com")
            #expect(part.title == "Example")
        } else {
            Issue.record("Expected .sourceURL part")
        }
    }

    // MARK: - sourceDocument chunk → .sourceDocument part

    @Test func reducerAppendsSourceDocumentPartFromSourceDocumentChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-srcdoc")
        reducer.apply(.sourceDocument(
            sourceId: "doc-1", mediaType: "application/pdf",
            title: "Research Paper", filename: "paper.pdf"
        ))

        let sources = reducer.message.sources
        #expect(sources.count == 1)
        if case .sourceDocument(let part) = sources[0] {
            #expect(part.id == "doc-1")
            #expect(part.mediaType == "application/pdf")
            #expect(part.title == "Research Paper")
            #expect(part.filename == "paper.pdf")
        } else {
            Issue.record("Expected .sourceDocument part")
        }
    }

    // MARK: - file chunk → .file part

    @Test func reducerAppendsFilePartFromFileChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-file")
        reducer.apply(.file(url: "https://files.example.com/doc.pdf", mediaType: "application/pdf"))

        let parts = reducer.message.parts
        #expect(parts.count == 1)
        if case .file(let fp) = parts[0] {
            #expect(fp.url == "https://files.example.com/doc.pdf")
            #expect(fp.mediaType == "application/pdf")
        } else {
            Issue.record("Expected .file part")
        }
    }

    // MARK: - transient data parts

    @Test func reducerCreatesTransientDataPartWhenTransientTrue() {
        var reducer = UIMessageStreamReducer(messageId: "msg-transient")
        reducer.apply(.data(name: "plan", payload: .string("do research"), isTransient: true, dataId: "plan-001"))

        let dataParts = reducer.message.dataParts
        #expect(dataParts.isEmpty)
    }

    @Test func reducerCreatesNonTransientDataPartByDefault() {
        var reducer = UIMessageStreamReducer(messageId: "msg-non-transient")
        reducer.apply(.data(name: "steps", payload: .array([.string("step1")])))

        let dataParts = reducer.message.dataParts
        #expect(dataParts.count == 1)
        #expect(dataParts[0].isTransient == false)
        #expect(dataParts[0].id == nil)
    }

    @Test func reducerReconcilesDataPartByMatchingIdAndName() {
        var reducer = UIMessageStreamReducer(messageId: "msg-reconcile")
        reducer.apply(.data(name: "plan", payload: .string("draft"), isTransient: false, dataId: "plan-1"))
        reducer.apply(.data(name: "plan", payload: .string("final"), isTransient: false, dataId: "plan-1"))

        let dataParts = reducer.message.dataParts
        #expect(dataParts.count == 1)
        #expect(dataParts[0].id == "plan-1")
        #expect(dataParts[0].researchPlan == "final")
    }

    // MARK: - finishReason

    @Test func reducerStoresFinishReasonFromFinishChunk() {
        var reducer = UIMessageStreamReducer(messageId: "msg-fr")
        reducer.apply(.finish(finishReason: "stop"))

        #expect(reducer.finishReason == "stop")
        #expect(reducer.isFinished == true)
    }

    @Test func reducerFinishReasonNilWhenNotProvided() {
        var reducer = UIMessageStreamReducer(messageId: "msg-fr-nil")
        reducer.apply(.finish())

        #expect(reducer.finishReason == nil)
        #expect(reducer.isFinished == true)
    }
}

// MARK: - DataPart Codable with new fields

struct DataPartCodableTests {

    @Test func dataPartWithIsTransientAndIdRoundTrips() throws {
        let original = DataPart(name: "plan", data: .string("do research"), isTransient: true, id: "plan-42")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DataPart.self, from: encoded)
        #expect(decoded.name == "plan")
        #expect(decoded.data.stringValue == "do research")
        #expect(decoded.isTransient == true)
        #expect(decoded.id == "plan-42")
    }

    @Test func dataPartDefaultFieldsRoundTrip() throws {
        let original = DataPart(name: "usage", data: .null)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DataPart.self, from: encoded)
        #expect(decoded.isTransient == false)
        #expect(decoded.id == nil)
    }

    @Test func dataPartResearchPlanAccessor() {
        let part = DataPart(name: "plan", data: .string("search for AI papers"))
        #expect(part.researchPlan == "search for AI papers")
    }

    @Test func dataPartResearchPlanReturnsNilForWrongName() {
        let part = DataPart(name: "steps", data: .string("search for AI papers"))
        #expect(part.researchPlan == nil)
    }

    @Test func dataPartResearchStepsAccessor() {
        let part = DataPart(name: "steps", data: .array([.string("step1"), .string("step2")]))
        let steps = part.researchSteps
        #expect(steps?.count == 2)
        #expect(steps?[0] == "step1")
        #expect(steps?[1] == "step2")
    }

    @Test func dataPartResearchStepsReturnsNilForWrongName() {
        let part = DataPart(name: "plan", data: .array([.string("step1")]))
        #expect(part.researchSteps == nil)
    }
}

// MARK: - Tool error/approval reducer tests

struct ReducerToolErrorApprovalTests {

    @Test func toolInputErrorCreatesPartWithOutputErrorState() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tie")
        reducer.apply(.toolInputError(
            toolCallId: "tc1", toolName: "search",
            input: .object(["q": .string("go")]), errorText: "invalid args"
        ))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .outputError)
        #expect(invocations[0].errorText == "invalid args")
        #expect(invocations[0].toolName == "search")
    }

    @Test func toolInputErrorUpdatesExistingPart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tie-update")
        reducer.apply(.toolInputStart(toolCallId: "tc1", toolName: "search"))
        reducer.apply(.toolInputError(
            toolCallId: "tc1", toolName: "search",
            input: .null, errorText: "schema mismatch"
        ))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .outputError)
        #expect(invocations[0].errorText == "schema mismatch")
    }

    @Test func toolOutputErrorSetsErrorStateOnExistingPart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-toe")
        reducer.apply(.toolInputAvailable(toolCallId: "tc1", toolName: "calc", input: .null))
        reducer.apply(.toolOutputError(toolCallId: "tc1", errorText: "execution failed"))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .outputError)
        #expect(invocations[0].errorText == "execution failed")
    }

    @Test func toolOutputErrorIgnoresUnknownToolCallId() {
        var reducer = UIMessageStreamReducer(messageId: "msg-toe-unknown")
        reducer.apply(.toolOutputError(toolCallId: "unknown", errorText: "oops"))
        #expect(reducer.message.toolInvocations.isEmpty)
    }

    @Test func toolOutputDeniedSetsOutputDeniedState() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tod")
        reducer.apply(.toolInputAvailable(toolCallId: "tc1", toolName: "delete", input: .null))
        reducer.apply(.toolOutputDenied(toolCallId: "tc1"))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .outputDenied)
    }

    @Test func toolOutputDeniedIgnoresUnknownToolCallId() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tod-unknown")
        reducer.apply(.toolOutputDenied(toolCallId: "unknown"))
        #expect(reducer.message.toolInvocations.isEmpty)
    }

    @Test func toolApprovalRequestCreatesPartWithApprovalRequestedState() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tar")
        reducer.apply(.toolApprovalRequest(
            approvalId: "ap1", toolCallId: "tc1",
            toolName: "delete", input: .object(["id": .string("x")])
        ))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .approvalRequested)
        #expect(invocations[0].approvalId == "ap1")
        #expect(invocations[0].toolName == "delete")
    }

    @Test func toolApprovalRequestUpdatesExistingPart() {
        var reducer = UIMessageStreamReducer(messageId: "msg-tar-update")
        reducer.apply(.toolInputAvailable(toolCallId: "tc1", toolName: "delete", input: .null))
        reducer.apply(.toolApprovalRequest(
            approvalId: "ap2", toolCallId: "tc1",
            toolName: "delete", input: .null
        ))
        let invocations = reducer.message.toolInvocations
        #expect(invocations.count == 1)
        #expect(invocations[0].state == .approvalRequested)
        #expect(invocations[0].approvalId == "ap2")
    }
}

// MARK: - UIMessage Codable with metadata

struct UIMessageMetadataCodableTests {

    @Test func uiMessageWithMetadataRoundTrips() throws {
        let metadata: [String: JSONValue] = ["model": .string("gpt-4o"), "tokens": .int(500)]
        let original = UIMessage(id: "msg-1", role: .assistant, metadata: metadata)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIMessage.self, from: encoded)
        #expect(decoded.id == "msg-1")
        #expect(decoded.metadata?["model"]?.stringValue == "gpt-4o")
        #expect(decoded.metadata?["tokens"]?.intValue == 500)
    }

    @Test func uiMessageWithNilMetadataRoundTrips() throws {
        let original = UIMessage(id: "msg-2", role: .user)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIMessage.self, from: encoded)
        #expect(decoded.metadata == nil)
    }
}
