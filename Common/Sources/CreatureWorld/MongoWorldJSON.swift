import MongoKitten
import WorldCore

enum MongoWorldJSONError: Error, Equatable, Sendable {
    case missingObject
    case unsupportedPrimitive(String)
}

enum MongoWorldJSON {
    static func object(from primitive: Primitive?) throws -> [String: WorldJSONValue] {
        guard let document = primitive as? Document, !document.isArray else {
            throw MongoWorldJSONError.missingObject
        }
        return try Dictionary(
            uniqueKeysWithValues: document.pairs.map { pair in
                (pair.key, try value(from: pair.value))
            }
        )
    }

    static func value(from primitive: Primitive) throws -> WorldJSONValue {
        switch primitive {
        case is Null:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Double:
            return .number(value)
        case let value as Int32:
            return .number(Double(value))
        case let value as Int:
            return .number(Double(value))
        case let value as String:
            return .string(value)
        case let document as Document where document.isArray:
            return .array(try document.values.map(value(from:)))
        case let document as Document:
            return .object(try object(from: document))
        default:
            throw MongoWorldJSONError.unsupportedPrimitive(String(reflecting: type(of: primitive)))
        }
    }
}
