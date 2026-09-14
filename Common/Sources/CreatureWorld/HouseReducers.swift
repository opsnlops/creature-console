import Foundation
import WorldCore

/// What the house tells the world, as facts: doors, motion, people, measurements, and the
/// lighting scenes it offers and is set to. The adapter (`creature-house`) owns Home Assistant's
/// vocabulary; by the time an event is here it is already about a place or a person.
struct HouseReducer: WorldReducer {
    let eventTypes: Set<WorldEventType> = [
        HouseEvents.doorLocked, HouseEvents.doorUnlocked, HouseEvents.doorOpened,
        HouseEvents.doorClosed, HouseEvents.motionDetected, HouseEvents.motionCleared,
        HouseEvents.personSeen, HouseEvents.vehicleSeen, HouseEvents.animalSeen,
        HouseEvents.cameraWatching,
        HouseEvents.personArrived, HouseEvents.personLeft, HouseEvents.measurementChanged,
        HouseEvents.scenesOffered, HouseEvents.sceneRequested, HouseEvents.sceneActivated,
    ]

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard let subject = event.subjectIDs.first else { return WorldReduction() }
        let producer = FactProducer(kind: PresenceFacts.producerKind, id: "house", version: "1")
        func fact(_ predicate: String, _ value: WorldJSONValue, validFor: TimeInterval? = nil)
            throws -> Fact
        {
            try Fact(
                subjectID: subject,
                predicate: predicate,
                value: value,
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: event.occurredAt,
                validTo: validFor.map { event.occurredAt.addingTimeInterval($0) },
                derivedFrom: [.event(event.eventID)],
                producer: producer
            )
        }
        switch event.type {
        case HouseEvents.doorLocked:
            return WorldReduction(changedFacts: [try fact(WorldFacts.doorLock, .string("locked"))])
        case HouseEvents.doorUnlocked:
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.doorLock, .string("unlocked"))
            ])
        case HouseEvents.doorOpened:
            return WorldReduction(changedFacts: [try fact(WorldFacts.doorState, .string("open"))])
        case HouseEvents.doorClosed:
            return WorldReduction(changedFacts: [try fact(WorldFacts.doorState, .string("closed"))])
        case HouseEvents.motionDetected:
            // Motion is a moment, not a state: it stops being news on its own.
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.motionActive, .bool(true), validFor: Self.motionLifetime)
            ])
        case HouseEvents.motionCleared:
            return WorldReduction(changedFacts: [try fact(WorldFacts.motionActive, .bool(false))])
        case HouseEvents.cameraWatching:
            return WorldReduction(changedFacts: [try fact(WorldFacts.cameraWatching, .bool(true))])
        case HouseEvents.personSeen, HouseEvents.vehicleSeen, HouseEvents.animalSeen:
            let what =
                switch event.type {
                case HouseEvents.personSeen: "person"
                case HouseEvents.vehicleSeen: "vehicle"
                default: "animal"
                }
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.seenPrefix + what, .bool(true), validFor: Self.motionLifetime)
            ])
        case HouseEvents.personArrived:
            // Evidence: this supersedes the configured assumption for the same person.
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.personState, .string(PersonPresenceState.home.rawValue))
            ])
        case HouseEvents.personLeft:
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.personState, .string(PersonPresenceState.away.rawValue))
            ])
        case HouseEvents.measurementChanged:
            guard case .string(let predicate)? = event.payload["predicate"],
                let value = event.payload["value"]
            else { return WorldReduction() }
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.environmentPrefix + predicate, value)
            ])
        case HouseEvents.scenesOffered:
            guard let scenes = event.payload["scenes"] else { return WorldReduction() }
            return WorldReduction(changedFacts: [try fact(WorldFacts.houseScenes, scenes)])
        case HouseEvents.sceneRequested:
            guard let scene = event.payload["scene"] else { return WorldReduction() }
            return WorldReduction(changedFacts: [
                try fact(WorldFacts.houseSceneRequested, scene, validFor: Self.requestLifetime)
            ])
        case HouseEvents.sceneActivated:
            guard let scene = event.payload["scene"] else { return WorldReduction() }
            return WorldReduction(changedFacts: [try fact(WorldFacts.houseScene, scene)])
        default:
            return WorldReduction()
        }
    }

    static let motionLifetime: TimeInterval = 10 * 60
    static let requestLifetime: TimeInterval = 120
}
