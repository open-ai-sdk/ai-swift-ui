import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Custom data-* chunk decoding and typed accessor tests

struct CustomDataChunkDecodingAndTypedHelpersTests {

    let decoder = UIMessageChunkDecoder()

    // MARK: - data-usage

    @Test func decodesDataUsageChunk() throws {
        let json = #"data: {"type":"data-usage","data":{"promptTokens":120,"completionTokens":45,"totalTokens":165}}"#
        let chunk = try decoder.decode(json)
        guard case .data(let name, let payload) = chunk else {
            Issue.record("Expected .data chunk"); return
        }
        #expect(name == "usage")
        guard case .object(let obj) = payload else {
            Issue.record("Expected object payload"); return
        }
        #expect(obj["promptTokens"]?.intValue == 120)
        #expect(obj["completionTokens"]?.intValue == 45)
        #expect(obj["totalTokens"]?.intValue == 165)
    }

    @Test func dataPartUsageTokensAccessor() {
        let data = JSONValue.object([
            "promptTokens": .int(100),
            "completionTokens": .int(50),
            "totalTokens": .int(150),
        ])
        let part = DataPart(name: "usage", data: data)
        let usage = part.usageTokens
        #expect(usage?.promptTokens == 100)
        #expect(usage?.completionTokens == 50)
        #expect(usage?.totalTokens == 150)
    }

    @Test func dataPartUsageTokensReturnsNilForWrongName() {
        let data = JSONValue.object([
            "promptTokens": .int(100),
            "completionTokens": .int(50),
            "totalTokens": .int(150),
        ])
        let part = DataPart(name: "other", data: data)
        #expect(part.usageTokens == nil)
    }

    @Test func dataPartUsageTokensReturnsNilForMissingFields() {
        let part = DataPart(name: "usage", data: .object(["promptTokens": .int(10)]))
        #expect(part.usageTokens == nil)
    }

    @Test func uiMessageUsageTokensHelper() throws {
        let usageChunk = UIMessageChunk.data(
            name: "usage",
            payload: .object([
                "promptTokens": .int(200),
                "completionTokens": .int(80),
                "totalTokens": .int(280),
            ])
        )
        var reducer = UIMessageStreamReducer(messageId: "msg-usage")
        reducer.apply(.start(messageId: "msg-usage"))
        reducer.apply(.startStep)
        reducer.apply(.textStart(id: "t1"))
        reducer.apply(.textDelta(id: "t1", delta: "answer"))
        reducer.apply(.textEnd(id: "t1"))
        reducer.apply(.finishStep)
        reducer.apply(usageChunk)
        reducer.apply(.finish)

        let usage = reducer.message.usageTokens
        #expect(usage?.promptTokens == 200)
        #expect(usage?.completionTokens == 80)
        #expect(usage?.totalTokens == 280)
    }

    // MARK: - data-document-references

    @Test func decodesDataDocumentReferencesChunk() throws {
        let payload = #"{"type":"data-document-references","data":"#
            + #"[{"id":"doc-1","title":"Go Book"},"#
            + #"{"id":"doc-2","title":"Concurrency Guide"}]}"#
        let json = "data: " + payload
        let chunk = try decoder.decode(json)
        guard case .data(let name, let payload) = chunk else {
            Issue.record("Expected .data chunk"); return
        }
        #expect(name == "document-references")
        guard case .array(let items) = payload else {
            Issue.record("Expected array payload"); return
        }
        #expect(items.count == 2)
        if case .object(let first) = items[0] {
            #expect(first["id"]?.stringValue == "doc-1")
            #expect(first["title"]?.stringValue == "Go Book")
        } else {
            Issue.record("Expected object at index 0")
        }
    }

    @Test func reducerPromotesDocumentReferencesToSourceDocumentParts() throws {
        let chunks: [UIMessageChunk] = [
            .start(messageId: "msg-docs"),
            .startStep,
            .data(name: "document-references", payload: .array([
                .object(["id": .string("doc-1"), "title": .string("Go Book")]),
                .object(["id": .string("doc-2"), "title": .string("Concurrency Guide")]),
            ])),
            .finishStep,
            .finish,
        ]
        var reducer = UIMessageStreamReducer(messageId: "msg-docs")
        reducer.applyAll(chunks)

        let docRefs = reducer.message.documentReferences
        #expect(docRefs.count == 2)
        #expect(docRefs[0].id == "doc-1")
        #expect(docRefs[0].title == "Go Book")
        #expect(docRefs[1].id == "doc-2")
        #expect(docRefs[1].title == "Concurrency Guide")

        // Should not appear as generic DataPart
        #expect(reducer.message.dataParts.filter { $0.name == "document-references" }.isEmpty)
    }

    @Test func reducerHandlesEmptyDocumentReferencesArray() {
        var reducer = UIMessageStreamReducer(messageId: "msg-empty-docs")
        reducer.apply(.start(messageId: "msg-empty-docs"))
        reducer.apply(.data(name: "document-references", payload: .array([])))
        reducer.apply(.finish)

        #expect(reducer.message.documentReferences.isEmpty)
        #expect(reducer.message.dataParts.isEmpty)
    }

    @Test func reducerSkipsMalformedDocumentReferenceItems() {
        let chunks: [UIMessageChunk] = [
            .start(messageId: "msg-malformed"),
            .data(name: "document-references", payload: .array([
                .string("not-an-object"),
                .object(["id": .string("doc-ok"), "title": .string("Valid Doc")]),
            ])),
            .finish,
        ]
        var reducer = UIMessageStreamReducer(messageId: "msg-malformed")
        reducer.applyAll(chunks)

        let docRefs = reducer.message.documentReferences
        #expect(docRefs.count == 1)
        #expect(docRefs[0].id == "doc-ok")
    }

    // MARK: - data-suggested-questions

    @Test func decodesDataSuggestedQuestionsChunk() throws {
        let json = #"data: {"type":"data-suggested-questions","data":{"questions":["What is X?","How does Y work?"]}}"#
        let chunk = try decoder.decode(json)
        guard case .data(let name, let payload) = chunk else {
            Issue.record("Expected .data chunk"); return
        }
        #expect(name == "suggested-questions")
        guard case .object(let obj) = payload,
              case .array(let qs) = obj["questions"] else {
            Issue.record("Expected questions array"); return
        }
        #expect(qs.count == 2)
        #expect(qs[0].stringValue == "What is X?")
        #expect(qs[1].stringValue == "How does Y work?")
    }

    @Test func dataPartSuggestedQuestionsAccessor() {
        let part = DataPart(name: "suggested-questions", data: .object([
            "questions": .array([.string("Q1"), .string("Q2"), .string("Q3")]),
        ]))
        let questions = part.suggestedQuestions
        #expect(questions?.count == 3)
        #expect(questions?[0] == "Q1")
        #expect(questions?[2] == "Q3")
    }

    @Test func dataPartSuggestedQuestionsReturnsNilForWrongName() {
        let part = DataPart(name: "other", data: .object([
            "questions": .array([.string("Q1")]),
        ]))
        #expect(part.suggestedQuestions == nil)
    }

    @Test func uiMessageSuggestedQuestionsHelper() {
        let chunks: [UIMessageChunk] = [
            .start(messageId: "msg-sq"),
            .startStep,
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "answer"),
            .textEnd(id: "t1"),
            .finishStep,
            .data(name: "suggested-questions", payload: .object([
                "questions": .array([.string("Follow-up A"), .string("Follow-up B")]),
            ])),
            .finish,
        ]
        var reducer = UIMessageStreamReducer(messageId: "msg-sq")
        reducer.applyAll(chunks)

        let questions = reducer.message.suggestedQuestions
        #expect(questions?.count == 2)
        #expect(questions?[0] == "Follow-up A")
    }
}
