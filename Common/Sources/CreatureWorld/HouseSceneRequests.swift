import Foundation
import Logging
import WorldCore

/// The world's side of "set the lights to …": match the words against the scenes the house
/// has offered (the `house.scenes` fact), announce a `house.scene_requested` event for the
/// adapter to act on, and hand back the fact the mind is told.
struct HouseSceneRequests: HouseCommandRecognizing {
    static let sourceID = try! SourceID(validating: "world:house-commands")
    static let requestLifetime: TimeInterval = 120

    let facts: FactRepository
    let world: World
    let clock: any WorldClock
    let logger: Logger
    private let rule = SceneRequestRule()

    func request(in utterance: PersonUtterance) async throws -> Fact? {
        let now = await clock.now
        for (house, scenes) in try await Self.offered(by: facts, at: now) {
            guard let scene = rule.scene(in: utterance.text, offered: scenes) else { continue }
            let event = try WorldEventEnvelope(
                type: HouseEvents.sceneRequested,
                occurredAt: now,
                source: EventSource(
                    id: Self.sourceID, kind: "world",
                    sourceEventID: utterance.utteranceID.rawValue),
                subjectIDs: [house, utterance.speakerID],
                epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: [
                    "scene": .string(scene),
                    "requested_by": .string(utterance.speakerID.rawValue),
                    "utterance_id": .string(utterance.utteranceID.rawValue),
                ],
                causedBy: [],
                trace: utterance.trace
            )
            let accepted = try await world.accept(event)
            logger.info(
                "A scene was asked for",
                metadata: [
                    "house.scene": "\(scene)",
                    "world.event_id": "\(accepted.event.eventID.rawValue)",
                ])
            return try Fact(
                subjectID: house,
                predicate: WorldFacts.houseSceneRequested,
                value: .string(scene),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: now,
                validTo: now.addingTimeInterval(Self.requestLifetime),
                derivedFrom: [.event(accepted.event.eventID)],
                producer: FactProducer(kind: PresenceFacts.producerKind, id: "house", version: "1")
            )
        }
        return nil
    }

    /// Which house offers scenes, and which: one house today, but the facts say so.
    static func offered(by facts: FactRepository, at now: Date) async throws
        -> [(house: EntityID, scenes: [String])]
    {
        var offered: [(house: EntityID, scenes: [String])] = []
        for house in try await facts.subjects(withPredicate: WorldFacts.houseScenes, at: now) {
            let fact = try await facts.currentFacts(subjectID: house, at: now)
                .first { $0.predicate == WorldFacts.houseScenes }
            guard case .array(let names)? = fact?.value else { continue }
            offered.append(
                (
                    house,
                    names.compactMap { value -> String? in
                        if case .string(let name) = value { return name }
                        return nil
                    }
                ))
        }
        return offered
    }
}

/// The mind's side of asking the house (#240): what `GET /v1/house/asks` tells a mind, and the
/// guard on a mind's own `house.scene_requested` - accepted only when the mind decides, only
/// for a scene the house offers, and named as the house names it.
struct HouseAskDesk: Sendable {
    let mode: HouseAskMode
    let facts: FactRepository
    let clock: any WorldClock

    func asks() async throws -> HouseAsks {
        guard mode == .mind else { return HouseAsks(askedBy: mode, scenes: []) }
        let offered = try await HouseSceneRequests.offered(by: facts, at: await clock.now)
        return HouseAsks(askedBy: mode, scenes: offered.flatMap(\.scenes))
    }

    /// The event as the world keeps it; a mind's request it may not make is refused.
    func check(_ event: WorldEventEnvelope) async throws -> WorldEventEnvelope {
        guard event.type == HouseEvents.sceneRequested, event.source.kind == "mind" else {
            return event
        }
        guard mode == .mind else {
            throw WorldContractError.refusedHouseAsk("the world decides house asks by its words")
        }
        guard case .string(let asked)? = event.payload["scene"],
            let scene = try await asks().scene(named: asked)
        else {
            throw WorldContractError.refusedHouseAsk("the house offers no such scene")
        }
        var checked = event
        checked.payload["scene"] = .string(scene)
        return checked
    }
}
