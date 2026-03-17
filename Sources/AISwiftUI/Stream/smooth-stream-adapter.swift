import Foundation

/// Wraps a `UIMessageChunk` stream and re-emits `textDelta` chunks word-by-word
/// with a configurable inter-word delay, producing a smooth typewriter effect.
///
/// All non-`textDelta` chunks pass through immediately.
/// Any buffered text is flushed when a `textEnd`, `finish`, or `error` chunk arrives.
///
/// - Parameters:
///   - upstream: The source async stream of UI message chunks.
///   - delay: The pause inserted between each emitted word. Defaults to 12 ms.
/// - Returns: A new stream with the same chunks, smoothed for `textDelta` events.
public func smoothStream(
    _ upstream: AsyncThrowingStream<UIMessageChunk, any Error>,
    delay: Duration = .milliseconds(12)
) -> AsyncThrowingStream<UIMessageChunk, any Error> {
    AsyncThrowingStream { continuation in
        Task {
            // Buffer: (blockId, accumulated text not yet emitted)
            var textBuffers: [String: String] = [:]

            /// Flush all words in `buffer` for the given block ID, emitting one chunk per word.
            /// The final fragment (no trailing space) is kept in the buffer unless `force` is true.
            func flush(id: String, force: Bool) async throws {
                guard let buf = textBuffers[id], !buf.isEmpty else { return }

                // Split on whitespace boundaries, preserving separators
                var words: [String] = []
                var current = ""
                for char in buf {
                    current.append(char)
                    if char.isWhitespace {
                        words.append(current)
                        current = ""
                    }
                }

                // Emit complete word tokens (those ending with whitespace)
                for word in words {
                    continuation.yield(.textDelta(id: id, delta: word))
                    try await Task.sleep(for: delay)
                }

                if force {
                    // Emit the trailing fragment and clear
                    if !current.isEmpty {
                        continuation.yield(.textDelta(id: id, delta: current))
                    }
                    textBuffers[id] = nil
                } else {
                    // Hold the trailing fragment for the next delta
                    textBuffers[id] = current
                }
            }

            do {
                for try await chunk in upstream {
                    switch chunk {
                    case .textDelta(let id, let delta):
                        textBuffers[id, default: ""] += delta
                        try await flush(id: id, force: false)

                    case .textEnd(let id):
                        try await flush(id: id, force: true)
                        continuation.yield(chunk)

                    case .finish, .error:
                        for id in Array(textBuffers.keys) {
                            try await flush(id: id, force: true)
                        }
                        continuation.yield(chunk)

                    default:
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
