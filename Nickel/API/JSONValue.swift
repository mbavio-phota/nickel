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

    /// Keys that commonly wrap human-readable text in agent transcript events, in
    /// priority order. Recursed into (not just read as strings) because providers nest
    /// them arbitrarily, e.g. `{message: {content: [{type: "text", text: "..."}]}}`.
    private static let textCarrierKeys = [
        "text", "message", "content", "parts", "blocks", "body", "output_text", "value",
    ]

    /// Best-effort human-readable text dug out of the shapes agent transcript events use.
    /// Plain strings pass through; objects are searched recursively via well-known
    /// carrier keys; arrays concatenate whatever text their elements yield. Returns `nil`
    /// if nothing recognizable is found — callers should fall back to a raw-JSON
    /// disclosure view rather than assuming a schema.
    var displayText: String? {
        let text = extractText(depth: 0)
        return text?.isEmpty == false ? text : nil
    }

    private func extractText(depth: Int) -> String? {
        guard depth < 6 else {
            return nil
        }
        switch self {
        case .string(let value):
            return value
        case .object:
            for key in Self.textCarrierKeys {
                if let text = self[key]?.extractText(depth: depth + 1) {
                    return text
                }
            }
            return nil
        case .array(let elements):
            let pieces = elements.compactMap { $0.extractText(depth: depth + 1) }
            return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
        default:
            return nil
        }
    }

    /// The `role` field commonly embedded in transcript event payloads ("user",
    /// "assistant", ...), searched one level of `message` nesting deep.
    var roleValue: String? {
        self["role"]?.stringValue ?? self["message"]?["role"]?.stringValue
    }
}
