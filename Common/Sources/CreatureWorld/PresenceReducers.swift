import Foundation
import WorldCore

/// The world's first facts: who is where, derived from what the world itself observed.
enum PresenceFacts {
    static let producerKind = "reducer"
}

/// `character.logged_in` / `character.logged_out` → `presence.region` for the character.
/// "Mango and Kenny are here with you" becomes something the world knows, not a guess.
struct CharacterPresenceReducer: WorldReducer {
    let eventTypes: Set<WorldEventType> = [
        CharacterSessionService.loginEventType, CharacterSessionService.logoutEventType,
    ]

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard case .string(let rawCharacter)? = event.payload["character_id"],
            let character = EntityID(rawValue: rawCharacter),
            case .string(let rawRegion)? = event.payload["region_id"]
        else { return WorldReduction() }
        let present = event.type == CharacterSessionService.loginEventType
        let fact = try Fact(
            subjectID: character,
            predicate: WorldFacts.characterRegion,
            value: present ? .string(rawRegion) : .null,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: event.occurredAt,
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(
                kind: PresenceFacts.producerKind, id: "character-presence", version: "1")
        )
        return WorldReduction(changedFacts: [fact])
    }
}

/// A configured presence assumption, announced as a world event at startup so the fact it
/// becomes has provenance like any other.
struct AssumedPresenceAnnouncement {
    static let eventType = WorldEventType(rawValue: "presence.assumed")!
    static let sourceID = try! SourceID(validating: "world:presence-assumptions")

    static func events(for configuration: PresenceConfiguration, at now: Date) throws
        -> [WorldEventEnvelope]
    {
        try configuration.assumed.sorted { $0.key.rawValue < $1.key.rawValue }.map {
            person, assumption in
            try WorldEventEnvelope(
                type: eventType,
                occurredAt: now,
                source: EventSource(
                    id: sourceID, kind: "world",
                    // The same assumption announced again (a restart) is the same event.
                    sourceEventID:
                        "\(person.rawValue):\(assumption.state.rawValue):\(assumption.physicallyAudible):\(assumption.confidence)"
                ),
                subjectIDs: [person],
                epistemic: EpistemicState(type: .assumed, confidence: assumption.confidence),
                payload: [
                    "person_id": .string(person.rawValue),
                    "state": .string(assumption.state.rawValue),
                    "physically_audible": .bool(assumption.physicallyAudible),
                ]
            )
        }
    }
}

/// `presence.assumed` → `presence.state` / `presence.physically_audible` for the person, with
/// the assumption's confidence and `assumed` written on it, so the minds and the router read
/// the same thing and evidence can supersede it later.
struct AssumedPersonPresenceReducer: WorldReducer {
    let eventTypes: Set<WorldEventType> = [AssumedPresenceAnnouncement.eventType]

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard case .string(let rawPerson)? = event.payload["person_id"],
            let person = EntityID(rawValue: rawPerson),
            case .string(let state)? = event.payload["state"]
        else { return WorldReduction() }
        let audible: Bool
        if case .bool(let value)? = event.payload["physically_audible"] {
            audible = value
        } else {
            audible = false
        }
        let producer = FactProducer(
            kind: PresenceFacts.producerKind, id: "assumed-presence", version: "1")
        return WorldReduction(changedFacts: [
            try Fact(
                subjectID: person, predicate: WorldFacts.personState, value: .string(state),
                epistemic: event.epistemic, validFrom: event.occurredAt,
                derivedFrom: [.event(event.eventID)], producer: producer),
            try Fact(
                subjectID: person, predicate: WorldFacts.personAudible, value: .bool(audible),
                epistemic: event.epistemic, validFrom: event.occurredAt,
                derivedFrom: [.event(event.eventID)], producer: producer),
        ])
    }
}

/// `scene.performed` → `scene.last` for the region: what was just said, by whom, so the birds
/// can refer to it for a while.
struct SceneMemoryReducer: WorldReducer {
    static let predicate = WorldFacts.lastScene
    static let lifetime: TimeInterval = 3_600

    let eventTypes: Set<WorldEventType> = [SceneService.performedEventType]

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard let region = event.placeID, case .array? = event.payload["lines"] else {
            return WorldReduction()
        }
        var value: [String: WorldJSONValue] = [:]
        for key in ["scene_id", "trigger", "lines"] {
            if let entry = event.payload[key] {
                value[key] = entry
            }
        }
        let fact = try Fact(
            subjectID: region,
            predicate: Self.predicate,
            value: .object(value),
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: event.occurredAt,
            validTo: event.occurredAt.addingTimeInterval(Self.lifetime),
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(
                kind: PresenceFacts.producerKind, id: "scene-memory", version: "1")
        )
        return WorldReduction(changedFacts: [fact])
    }
}
