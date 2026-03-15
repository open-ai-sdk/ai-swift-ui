import Foundation

/// Parses SSE lines from the AI SDK UI message stream into `UIMessageChunk` values.
///
/// Feed individual SSE data lines (the string after `data: `) into `decode(_:)`.
/// The sentinel `data: [DONE]` returns `nil` to signal end-of-stream.
public struct UIMessageChunkDecoder: Sendable {

    public init() {}

    /// Attempt to decode a raw SSE line.
    ///
    /// - Parameter line: A full SSE event line, e.g. `data: {"type":"start","messageId":"x"}`.
    ///   Lines that do not begin with `data: ` are silently ignored (returns `nil`).
    ///   The sentinel `data: [DONE]` also returns `nil`.
    /// - Returns: The decoded `UIMessageChunk`, or `nil` for non-data / sentinel lines.
    public func decode(_ line: String) throws -> UIMessageChunk? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { return nil }

        guard let data = payload.data(using: .utf8) else {
            throw ChunkDecodingError.invalidUTF8
        }

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = raw["type"] as? String else {
            throw ChunkDecodingError.missingTypeField
        }

        return try parseChunk(type: type_, raw: raw, data: data)
    }

    // MARK: - Private parsing

    private func parseChunk(type: String, raw: [String: Any], data: Data) throws -> UIMessageChunk {
        switch type {
        case "start":
            let msgId = raw["messageId"] as? String ?? ""
            return .start(messageId: msgId)

        case "start-step":
            return .startStep

        case "finish-step":
            return .finishStep

        case "finish":
            return .finish

        case "error":
            let text = raw["errorText"] as? String ?? "unknown error"
            return .error(text: text)

        case "text-start":
            let id = raw["id"] as? String ?? ""
            return .textStart(id: id)

        case "text-delta":
            let id = raw["id"] as? String ?? ""
            let delta = raw["delta"] as? String ?? ""
            return .textDelta(id: id, delta: delta)

        case "text-end":
            let id = raw["id"] as? String ?? ""
            return .textEnd(id: id)

        case "reasoning-start":
            let id = raw["id"] as? String ?? ""
            return .reasoningStart(id: id)

        case "reasoning-delta":
            let id = raw["id"] as? String ?? ""
            let delta = raw["delta"] as? String ?? ""
            return .reasoningDelta(id: id, delta: delta)

        case "reasoning-end":
            let id = raw["id"] as? String ?? ""
            let sig = raw["signature"] as? String
            return .reasoningEnd(id: id, signature: sig)

        case "tool-input-start":
            let tcId = raw["toolCallId"] as? String ?? ""
            let name = raw["toolName"] as? String ?? ""
            return .toolInputStart(toolCallId: tcId, toolName: name)

        case "tool-input-delta":
            let tcId = raw["toolCallId"] as? String ?? ""
            let delta = raw["inputTextDelta"] as? String ?? ""
            return .toolInputDelta(toolCallId: tcId, inputTextDelta: delta)

        case "tool-input-available":
            let tcId = raw["toolCallId"] as? String ?? ""
            let name = raw["toolName"] as? String ?? ""
            let input = try decodeJSONValueField("input", from: raw)
            return .toolInputAvailable(toolCallId: tcId, toolName: name, input: input)

        case "tool-output-available":
            let tcId = raw["toolCallId"] as? String ?? ""
            let output = try decodeJSONValueField("output", from: raw)
            return .toolOutputAvailable(toolCallId: tcId, output: output)

        case "source":
            let id = raw["id"] as? String
            let url = raw["url"] as? String ?? ""
            let title = raw["title"] as? String
            return .source(id: id, url: url, title: title)

        case "sources":
            let sourcesRaw = raw["sources"] as? [[String: Any]] ?? []
            let sources = sourcesRaw.map { s in
                SourceURLPart(
                    id: s["id"] as? String,
                    url: s["url"] as? String ?? "",
                    title: s["title"] as? String
                )
            }
            return .sources(sources)

        default:
            // Handle data-* chunks
            if type.hasPrefix("data-") {
                let name = String(type.dropFirst(5))
                let payload: JSONValue
                if let dataField = raw["data"] {
                    let fieldData = try JSONSerialization.data(withJSONObject: dataField)
                    payload = try JSONDecoder().decode(JSONValue.self, from: fieldData)
                } else {
                    payload = .null
                }
                return .data(name: name, payload: payload)
            }
            throw ChunkDecodingError.unknownChunkType(type)
        }
    }

    private func decodeJSONValueField(_ key: String, from raw: [String: Any]) throws -> JSONValue {
        guard let fieldValue = raw[key] else { return .null }
        let fieldData = try JSONSerialization.data(withJSONObject: fieldValue)
        return try JSONDecoder().decode(JSONValue.self, from: fieldData)
    }
}

/// Errors that can occur during chunk decoding.
public enum ChunkDecodingError: Error, Sendable {
    case invalidUTF8
    case missingTypeField
    case unknownChunkType(String)
}
