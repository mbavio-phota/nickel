import Foundation

/// Represents arbitrary, untyped JSON — used for message `content`, which the Conductor
/// API deliberately leaves unschemad (agent transcript events vary by agent/tool).
indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue {
    /// The wrapped string, if this value is `.string`.
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// The wrapped number, if this value is `.number`.
    var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    /// The wrapped bool, if this value is `.bool`.
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// The wrapped array, if this value is `.array`.
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// The wrapped object, if this value is `.object`.
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Looks up a key when this value is `.object`; `nil` otherwise (never crashes).
    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Looks up an index when this value is `.array`; `nil` when out of bounds or not an
    /// array (never crashes).
    subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else {
            return nil
        }
        return array[index]
    }

    /// Best-effort human-readable text dug out of common shapes agent transcript events
    /// use ("text", "message", "content" as a string, or the value itself if it's already
    /// a plain string). Returns `nil` if nothing recognizable is found — callers should
    /// fall back to a raw-JSON disclosure view rather than assuming a schema.
    var displayText: String? {
        switch self {
        case .string(let value):
            return value
        case .object:
            for key in ["text", "message", "content"] {
                if let text = self[key]?.stringValue {
                    return text
                }
            }
            return nil
        default:
            return nil
        }
    }
}
