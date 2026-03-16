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
        if let lifecycle = parseLifecycleChunk(type: type, raw: raw) {
            return lifecycle
        }
        if let text = parseTextChunk(type: type, raw: raw) {
            return text
        }
        if let tool = try parseToolChunk(type: type, raw: raw) {
            return tool
        }
        if let source = parseSourceChunk(type: type, raw: raw) {
            return source
        }
        if let extended = try parseExtendedChunk(type: type, raw: raw) {
            return extended
        }
        if type.hasPrefix("data-") {
            return try parseDataChunk(type: type, raw: raw)
        }
        throw ChunkDecodingError.unknownChunkType(type)
    }

    private func parseLifecycleChunk(type: String, raw: [String: Any]) -> UIMessageChunk? {
        switch type {
        case "start":
            return .start(
                messageId: raw["messageId"] as? String ?? "",
                metadata: decodeMetadata(raw["messageMetadata"])
            )
        case "start-step": return .startStep
        case "finish-step": return .finishStep
        case "finish":
            return .finish(
                finishReason: raw["finishReason"] as? String,
                metadata: decodeMetadata(raw["messageMetadata"])
            )
        case "error": return .error(text: raw["errorText"] as? String ?? "unknown error")
        default: return nil
        }
    }

    private func parseTextChunk(type: String, raw: [String: Any]) -> UIMessageChunk? {
        let id = raw["id"] as? String ?? ""
        switch type {
        case "text-start": return .textStart(id: id)
        case "text-delta": return .textDelta(id: id, delta: raw["delta"] as? String ?? "")
        case "text-end": return .textEnd(id: id)
        case "reasoning-start": return .reasoningStart(id: id)
        case "reasoning-delta": return .reasoningDelta(id: id, delta: raw["delta"] as? String ?? "")
        case "reasoning-end": return .reasoningEnd(id: id, signature: raw["signature"] as? String)
        default: return nil
        }
    }

    private func parseToolChunk(type: String, raw: [String: Any]) throws -> UIMessageChunk? {
        let tcId = raw["toolCallId"] as? String ?? ""
        switch type {
        case "tool-input-start":
            return .toolInputStart(toolCallId: tcId, toolName: raw["toolName"] as? String ?? "")
        case "tool-input-delta":
            return .toolInputDelta(toolCallId: tcId, inputTextDelta: raw["inputTextDelta"] as? String ?? "")
        case "tool-input-available":
            let input = try decodeJSONValueField("input", from: raw)
            return .toolInputAvailable(toolCallId: tcId, toolName: raw["toolName"] as? String ?? "", input: input)
        case "tool-output-available":
            let output = try decodeJSONValueField("output", from: raw)
            return .toolOutputAvailable(toolCallId: tcId, output: output)
        default:
            return nil
        }
    }

    private func parseSourceChunk(type: String, raw: [String: Any]) -> UIMessageChunk? {
        switch type {
        case "source":
            return .source(id: raw["id"] as? String, url: raw["url"] as? String ?? "", title: raw["title"] as? String)
        case "sources":
            let sourcesRaw = raw["sources"] as? [[String: Any]] ?? []
            let sources = sourcesRaw.map { s in
                SourceURLPart(id: s["id"] as? String, url: s["url"] as? String ?? "", title: s["title"] as? String)
            }
            return .sources(sources)
        default:
            return nil
        }
    }

    private func parseDataChunk(type: String, raw: [String: Any]) throws -> UIMessageChunk {
        let name = String(type.dropFirst(5))
        let isTransient = raw["transient"] as? Bool ?? false
        let dataId = raw["id"] as? String
        guard let dataField = raw["data"] else {
            return .data(name: name, payload: .null, isTransient: isTransient, dataId: dataId)
        }
        let fieldData = try JSONSerialization.data(withJSONObject: dataField)
        let payload = try JSONDecoder().decode(JSONValue.self, from: fieldData)
        return .data(name: name, payload: payload, isTransient: isTransient, dataId: dataId)
    }

    private func parseExtendedChunk(type: String, raw: [String: Any]) throws -> UIMessageChunk? {
        switch type {
        case "message-metadata":
            let metaRaw = raw["messageMetadata"] as? [String: Any] ?? [:]
            var metadata: [String: JSONValue] = [:]
            for (key, value) in metaRaw {
                let wrapped = try JSONSerialization.data(withJSONObject: ["v": value])
                if let obj = try JSONDecoder().decode([String: JSONValue].self, from: wrapped)["v"] {
                    metadata[key] = obj
                }
            }
            return .messageMetadata(metadata: metadata)
        case "abort":
            return .abort(reason: raw["reason"] as? String)
        case "source-url":
            return .sourceURL(
                sourceId: raw["sourceId"] as? String ?? "",
                url: raw["url"] as? String ?? "",
                title: raw["title"] as? String
            )
        case "source-document":
            return .sourceDocument(
                sourceId: raw["sourceId"] as? String ?? "",
                mediaType: raw["mediaType"] as? String ?? "",
                title: raw["title"] as? String ?? "",
                filename: raw["filename"] as? String ?? ""
            )
        case "file":
            return .file(
                url: raw["url"] as? String ?? "",
                mediaType: raw["mediaType"] as? String ?? ""
            )
        default:
            return nil
        }
    }

    private func decodeJSONValueField(_ key: String, from raw: [String: Any]) throws -> JSONValue {
        guard let fieldValue = raw[key] else { return .null }
        let fieldData = try JSONSerialization.data(withJSONObject: fieldValue)
        return try JSONDecoder().decode(JSONValue.self, from: fieldData)
    }

    private func decodeMetadata(_ rawValue: Any?) -> [String: JSONValue]? {
        guard let metaRaw = rawValue as? [String: Any] else { return nil }
        var metadata: [String: JSONValue] = [:]
        for (key, value) in metaRaw {
            guard JSONSerialization.isValidJSONObject(["v": value]),
                  let wrapped = try? JSONSerialization.data(withJSONObject: ["v": value]),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: wrapped)["v"] else {
                continue
            }
            metadata[key] = decoded
        }
        return metadata
    }
}

/// Errors that can occur during chunk decoding.
public enum ChunkDecodingError: Error, Sendable {
    case invalidUTF8
    case missingTypeField
    case unknownChunkType(String)
}
