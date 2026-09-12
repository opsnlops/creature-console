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
        // Which house offers scenes, and which: one house today, but the facts say so.
        for house in try await facts.subjects(withPredicate: WorldFacts.houseScenes, at: now) {
            let offered = try await facts.currentFacts(subjectID: house, at: now)
                .first { $0.predicate == WorldFacts.houseScenes }
            guard case .array(let names)? = offered?.value else { continue }
            let scenes = names.compactMap { value -> String? in
                if case .string(let name) = value { return name }
                return nil
            }
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
}
