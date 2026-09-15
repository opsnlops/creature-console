import CreatureAppSupport
import Foundation
import WorldCore

/// Before a source casts a kind of fact the world has never held, it says what the kind means -
/// once. A meaning already in the glossary is never touched: a Wizard's rewording wins.
struct GlossarySeeder: Sendable {
    let client: WorldViewerClient
    let source: String

    func seed(_ meanings: [String: String]) async throws {
        let known = Set(try await client.factKinds().kinds.map(\.predicate))
        for (predicate, meaning) in meanings.sorted(by: { $0.key < $1.key })
        where !known.contains(predicate) {
            _ = try await client.setFactKind(
                predicate, FactKindUpdate(meaning: meaning, updatedBy: "bridge:\(source)"))
        }
    }
}
