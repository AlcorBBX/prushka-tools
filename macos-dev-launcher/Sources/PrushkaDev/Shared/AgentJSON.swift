import Foundation

enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    func data() -> Data {
        let payload = foundation
        guard JSONSerialization.isValidJSONObject(payload),
              let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else {
            return Data("null".utf8)
        }
        return encoded
    }

    private var foundation: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundation)
        case .object(let fields):
            return fields.mapValues(\.foundation)
        }
    }
}

enum AgentText {
    static func tail(_ text: String, max: Int = 64_000) -> String {
        guard text.count > max else { return text }
        return String(text.suffix(max))
    }
}
