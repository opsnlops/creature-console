import CreatureAppSupport
import Foundation
import WorldCore

/// Before a source casts a kind of fact, it says what the kind means. A kind the world has never
/// held is added; one the Bridge itself wrote last is brought up to date when its words change
/// - a reader improves, the meaning follows. A meaning anyone else last touched is never
/// changed: a Wizard's rewording wins.
struct GlossarySeeder: Sendable {
    let client: WorldViewerClient
    let source: String

    var author: String { "bridge:\(source)" }

    /// `worldOnly` names the kinds that are the world's alone - never in a prompt.
    func seed(_ meanings: [String: String], worldOnly: Set<String> = []) async throws {
        let known = Dictionary(
            try await client.factKinds().kinds.map { ($0.predicate, $0) },
            uniquingKeysWith: { first, _ in first })
        for (predicate, meaning) in meanings.sorted(by: { $0.key < $1.key }) {
            let audience: FactAudience = worldOnly.contains(predicate) ? .world : .minds
            if let existing = known[predicate] {
                guard existing.updatedBy == author,
                    existing.meaning != meaning || existing.audience != audience
                else { continue }
            }
            _ = try await client.setFactKind(
                predicate, FactKindUpdate(meaning: meaning, audience: audience, updatedBy: author))
        }
    }
}
