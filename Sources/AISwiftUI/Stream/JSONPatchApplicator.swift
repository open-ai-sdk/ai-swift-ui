/// Applies RFC 6902 JSON Patch operations to a `JSONValue` target.
///
/// Supports `add`, `replace`, and `remove` operations — sufficient for
/// consuming the json-render SpecStream format.
enum JSONPatchApplicator {

    enum PatchError: Error {
        case invalidPath
        case pathNotFound
        case invalidOperation
    }

    /// Apply a single JSON Patch operation (as a `JSONValue` object) to `target`.
    ///
    /// The operation must have `"op"`, `"path"`, and (for add/replace) `"value"` keys.
    static func apply(patch: JSONValue, to target: inout JSONValue) throws {
        guard case .object(let dict) = patch,
              case .string(let op) = dict["op"],
              case .string(let path) = dict["path"] else {
            throw PatchError.invalidOperation
        }

        let segments = parsePath(path)

        switch op {
        case "add":
            let value = dict["value"] ?? .null
            try insert(&target, at: segments, value: value)
        case "replace":
            let value = dict["value"] ?? .null
            try replace(&target, at: segments, value: value)
        case "remove":
            try remove(&target, at: segments)
        default:
            // move / copy / test are not used by SpecStream — silently ignore
            break
        }
    }

    // MARK: - Path parsing (RFC 6901)

    /// Splits a JSON Pointer path into key segments, applying `~0`/`~1` unescaping.
    private static func parsePath(_ path: String) -> [String] {
        guard path.hasPrefix("/") else { return [] }
        return path.dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                $0.replacingOccurrences(of: "~1", with: "/")
                  .replacingOccurrences(of: "~0", with: "~")
            }
    }

    // MARK: - Add

    private static func insert(_ target: inout JSONValue, at path: [String], value: JSONValue) throws {
        if path.isEmpty {
            target = value
            return
        }
        let key = path[0]
        let rest = Array(path.dropFirst())

        switch target {
        case .object(var dict):
            if rest.isEmpty {
                dict[key] = value
            } else {
                var nested = dict[key] ?? .object([:])
                try insert(&nested, at: rest, value: value)
                dict[key] = nested
            }
            target = .object(dict)

        case .array(var arr):
            if key == "-" && rest.isEmpty {
                arr.append(value)
                target = .array(arr)
            } else if let idx = Int(key) {
                if rest.isEmpty {
                    let clampedIdx = min(max(idx, 0), arr.count)
                    arr.insert(value, at: clampedIdx)
                } else if idx < arr.count {
                    var nested = arr[idx]
                    try insert(&nested, at: rest, value: value)
                    arr[idx] = nested
                }
                target = .array(arr)
            } else {
                throw PatchError.invalidPath
            }

        default:
            if rest.isEmpty {
                // promote scalar to object when adding a key
                target = .object([key: value])
            } else {
                throw PatchError.invalidPath
            }
        }
    }

    // MARK: - Replace

    private static func replace(_ target: inout JSONValue, at path: [String], value: JSONValue) throws {
        if path.isEmpty {
            target = value
            return
        }
        let key = path[0]
        let rest = Array(path.dropFirst())

        switch target {
        case .object(var dict):
            if rest.isEmpty {
                dict[key] = value
            } else {
                guard var nested = dict[key] else { throw PatchError.pathNotFound }
                try replace(&nested, at: rest, value: value)
                dict[key] = nested
            }
            target = .object(dict)

        case .array(var arr):
            guard let idx = Int(key), idx < arr.count else { throw PatchError.pathNotFound }
            if rest.isEmpty {
                arr[idx] = value
            } else {
                var nested = arr[idx]
                try replace(&nested, at: rest, value: value)
                arr[idx] = nested
            }
            target = .array(arr)

        default:
            throw PatchError.pathNotFound
        }
    }

    // MARK: - Remove

    private static func remove(_ target: inout JSONValue, at path: [String]) throws {
        if path.isEmpty {
            target = .null
            return
        }
        let key = path[0]
        let rest = Array(path.dropFirst())

        switch target {
        case .object(var dict):
            if rest.isEmpty {
                dict.removeValue(forKey: key)
            } else if var nested = dict[key] {
                try remove(&nested, at: rest)
                dict[key] = nested
            }
            target = .object(dict)

        case .array(var arr):
            guard let idx = Int(key), idx < arr.count else { throw PatchError.pathNotFound }
            if rest.isEmpty {
                arr.remove(at: idx)
            } else {
                var nested = arr[idx]
                try remove(&nested, at: rest)
                arr[idx] = nested
            }
            target = .array(arr)

        default:
            break
        }
    }
}
