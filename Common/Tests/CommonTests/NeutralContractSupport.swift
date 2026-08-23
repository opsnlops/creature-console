import Foundation
import Testing

@testable import Common

/// Shared helpers for the server-contract tests.
///
/// Server 3.45.0 omits an optional it has no value for and rejects an explicit `null` for one,
/// so "did this payload contain a null anywhere" is the single question worth asking of every
/// request the Console builds. Asking it structurally beats spot-checking individual keys —
/// a null nested three levels down inside stage placements counts just as much as one at the
/// top.
enum NeutralContract {

    /// Every path in an encoded payload that holds a JSON `null`, in `$.a.b[0]` form.
    /// Empty means the payload is clean.
    static func nullPaths(in value: Any, path: String = "$") -> [String] {
        if value is NSNull {
            return [path]
        }
        if let object = value as? [String: Any] {
            return object.sorted { $0.key < $1.key }.flatMap {
                nullPaths(in: $0.value, path: "\(path).\($0.key)")
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap {
                nullPaths(in: $0.element, path: "\(path)[\($0.offset)]")
            }
        }
        return []
    }

    /// Encode a value and hand back its JSON object form, ready to assert against.
    static func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try #require(object as? [String: Any])
    }

    /// Assert an encoded payload carries no JSON null at any depth.
    static func expectNoNulls<T: Encodable>(
        _ value: T, _ label: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let object = try encodedObject(value)
        let paths = nullPaths(in: object)
        #expect(
            paths.isEmpty,
            "\(label) encoded a JSON null at \(paths.joined(separator: ", "))",
            sourceLocation: sourceLocation)
    }
}

@Suite("Null-path helper")
struct NeutralContractSupportTests {

    @Test("finds nulls at every depth, and reports none when there are none")
    func findsNullsAtEveryDepth() {
        let payload: [String: Any] = [
            "top": NSNull(),
            "nested": ["inner": NSNull()],
            "list": [["deep": NSNull()], ["fine": 1]],
            "fine": "value",
        ]
        #expect(
            NeutralContract.nullPaths(in: payload)
                == ["$.list[0].deep", "$.nested.inner", "$.top"])
        #expect(NeutralContract.nullPaths(in: ["fine": 1, "also": ["fine"]]).isEmpty)
    }
}
