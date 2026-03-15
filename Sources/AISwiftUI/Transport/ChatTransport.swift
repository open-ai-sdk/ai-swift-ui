/// The transport abstraction for sending chat requests and receiving streamed chunks.
///
/// Conforming types handle the network/IPC layer; they receive a `TransportSendRequest`
/// and return an `AsyncThrowingStream` that emits `UIMessageChunk` values as the
/// response streams in.
public protocol ChatTransport: Sendable {
    func send(_ request: TransportSendRequest) -> AsyncThrowingStream<UIMessageChunk, any Error>
}
