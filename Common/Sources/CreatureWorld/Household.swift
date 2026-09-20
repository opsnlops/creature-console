import Foundation
import WorldCore

/// Who is about, as the house knows it, the moment a camera sees someone: April's presence
/// from the sensor, and whoever is expected. April lives alone; the stage note carries this so
/// the minds never guess at a shape. Read afresh for every occasion - a scene's note is about
/// now.
enum Household {
    static let april = try! EntityID(validating: "person:april")

    static func situation(facts: FactRepository, at now: Date) async throws -> HouseholdSituation {
        situation(
            aprilFacts: try await facts.currentFacts(subjectID: april, at: now),
            expected: try await facts.currentFacts(
                subjectID: nil, predicatePrefix: WorldFacts.visitorExpected, after: nil, limit: 5,
                at: now))
    }

    /// `presence.state` on April, and every `visitor.expected` in force - on the house, or on
    /// the person coming (the calendar's rule casts it there).
    static func situation(aprilFacts: [Fact], expected: [Fact]) -> HouseholdSituation {
        let home: Bool?
        if case .string(let state)? = aprilFacts.first(where: {
            $0.predicate == WorldFacts.personState
        })?.value {
            home = state == PersonPresenceState.home.rawValue
        } else {
            home = nil
        }
        let visitors = expected.compactMap { fact -> String? in
            guard case .string(let words) = fact.value, !words.isEmpty else { return nil }
            if fact.subjectID.rawValue.hasPrefix("person:") {
                return "\(SceneOpeningPolicy.placeName(fact.subjectID)), \(words)"
            }
            return words
        }
        return HouseholdSituation(
            aprilHome: home,
            visitorExpected: visitors.isEmpty ? nil : visitors.joined(separator: "; "))
    }
}
