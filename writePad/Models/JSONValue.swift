import Foundation

/// Any JSON value, kept verbatim so fields this build doesn't know survive a load and save.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// Reads and writes the keys of a JSON object that a type's own `CodingKeys` don't cover.
struct UnknownFields {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func decode(from decoder: Decoder, known: some Sequence<String>) throws -> [String: JSONValue] {
        let container = try decoder.container(keyedBy: Key.self)
        let known = Set(known)
        var fields: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        return fields
    }

    static func encode(_ fields: [String: JSONValue], to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in fields {
            try container.encode(value, forKey: Key(key))
        }
    }
}
