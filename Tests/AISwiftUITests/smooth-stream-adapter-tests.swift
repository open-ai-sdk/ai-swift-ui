import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Smooth Stream Adapter Tests

struct SmoothStreamAdapterTests {

    /// Helper: collect all chunks from a stream into an array.
    private func collect(_ stream: AsyncThrowingStream<UIMessageChunk, any Error>) async throws -> [UIMessageChunk] {
        var result: [UIMessageChunk] = []
        for try await chunk in stream {
            result.append(chunk)
        }
        return result
    }

    @Test func textDeltasAreSplitByWordBoundaries() async throws {
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.start(messageId: "m1"))
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: "Hello world "))
            continuation.yield(.textEnd(id: "t1"))
            continuation.yield(.finish())
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))
        let deltas = chunks.compactMap { chunk -> String? in
            if case .textDelta(_, let delta) = chunk { return delta }
            return nil
        }

        // "Hello world " should emit "Hello " and "world " as separate tokens
        #expect(deltas.count >= 2)
        let joined = deltas.joined()
        #expect(joined == "Hello world ")
    }

    @Test func nonTextChunksPassThroughImmediately() async throws {
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.start(messageId: "m2"))
            continuation.yield(.startStep)
            continuation.yield(.finish())
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))

        let types = chunks.map { chunk -> String in
            switch chunk {
            case .start: return "start"
            case .startStep: return "startStep"
            case .finish: return "finish"
            default: return "other"
            }
        }
        #expect(types.contains("start"))
        #expect(types.contains("startStep"))
        #expect(types.contains("finish"))
    }

    @Test func bufferFlushesOnTextEnd() async throws {
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.textStart(id: "t1"))
            // "fragment" has no trailing space — stays in buffer until textEnd forces flush
            continuation.yield(.textDelta(id: "t1", delta: "fragment"))
            continuation.yield(.textEnd(id: "t1"))
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))
        let deltas = chunks.compactMap { chunk -> String? in
            if case .textDelta(_, let delta) = chunk { return delta }
            return nil
        }
        let textEnds = chunks.filter {
            if case .textEnd = $0 { return true }
            return false
        }

        // fragment should be flushed before textEnd
        #expect(deltas.joined() == "fragment")
        // textEnd should appear after the delta
        #expect(!textEnds.isEmpty)
    }

    @Test func bufferFlushesOnFinish() async throws {
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: "pending"))
            continuation.yield(.finish())
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))
        let deltaTexts = chunks.compactMap { chunk -> String? in
            if case .textDelta(_, let d) = chunk { return d }
            return nil
        }

        // "pending" should be flushed before finish
        #expect(deltaTexts.joined() == "pending")
    }

    @Test func allTextContentPreservedNoDataLoss() async throws {
        // Emit text as two separate deltas and verify all content comes through
        let part1 = "Hello "
        let part2 = "World"
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: part1))
            continuation.yield(.textDelta(id: "t1", delta: part2))
            continuation.yield(.textEnd(id: "t1"))
            continuation.yield(.finish())
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))
        let reconstructed = chunks.compactMap { chunk -> String? in
            if case .textDelta(_, let d) = chunk { return d }
            return nil
        }.joined()

        #expect(reconstructed == part1 + part2)
    }

    @Test func multipleTextBlocksBufferedIndependently() async throws {
        let upstream = AsyncThrowingStream<UIMessageChunk, any Error> { continuation in
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: "Hello "))
            continuation.yield(.textEnd(id: "t1"))
            continuation.yield(.textStart(id: "t2"))
            continuation.yield(.textDelta(id: "t2", delta: "World "))
            continuation.yield(.textEnd(id: "t2"))
            continuation.yield(.finish())
            continuation.finish()
        }

        let chunks = try await collect(smoothStream(upstream, delay: .zero))
        let t1Deltas = chunks.compactMap { chunk -> String? in
            if case .textDelta("t1", let d) = chunk { return d }
            return nil
        }
        let t2Deltas = chunks.compactMap { chunk -> String? in
            if case .textDelta("t2", let d) = chunk { return d }
            return nil
        }

        #expect(t1Deltas.joined() == "Hello ")
        #expect(t2Deltas.joined() == "World ")
    }
}
