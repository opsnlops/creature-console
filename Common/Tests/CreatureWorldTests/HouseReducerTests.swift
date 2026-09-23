import Foundation
import Testing
import WorldCore

@testable import creature_world

@Suite("The house, as facts")
struct HouseReducerTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let frontDoor = try! EntityID(validating: "place:front-door")
    private let driveway = try! EntityID(validating: "place:driveway")
    private let april = try! EntityID(validating: "person:april")
    private let house = try! EntityID(validating: "house:aprils-nest")

    @Test("Doors, motion, sightings, people, measurements, and scenes each become a fact")
    func houseEventsBecomeFacts() throws {
        let reducer = HouseReducer()
        func reduce(
            _ type: WorldEventType, _ subject: EntityID, _ payload: [String: WorldJSONValue] = [:]
        )
            throws -> Fact?
        {
            try reducer.reduce(try event(type, subject, payload)).changedFacts.first
        }

        let unlocked = try #require(try reduce(HouseEvents.doorUnlocked, frontDoor))
        #expect(unlocked.predicate == WorldFacts.doorLock)
        #expect(unlocked.value == .string("unlocked"))
        #expect(unlocked.validTo == nil)
        #expect(unlocked.epistemic.type == .observed)

        let seen = try #require(try reduce(HouseEvents.vehicleSeen, driveway))
        #expect(seen.predicate == "seen.vehicle")
        #expect(seen.validTo == now.addingTimeInterval(HouseReducer.motionLifetime))

        let watching = try #require(try reduce(HouseEvents.cameraWatching, driveway))
        #expect(watching.predicate == WorldFacts.cameraWatching)
        #expect(watching.value == .bool(true))
        #expect(watching.validTo == nil)

        let motion = try #require(try reduce(HouseEvents.motionDetected, driveway))
        #expect(motion.predicate == WorldFacts.motionActive)
        #expect(motion.validTo != nil)

        let arrived = try #require(try reduce(HouseEvents.personArrived, april))
        #expect(arrived.predicate == WorldFacts.personState)
        #expect(arrived.value == .string("home"))
        #expect(arrived.epistemic.type == .observed)
        // Coming and going make whatever was reported about where the person is moot.
        for type in [HouseEvents.personArrived, HouseEvents.personLeft] {
            let retractions = try reducer.reduce(try event(type, april)).retractions
            #expect(retractions.map(\.predicatePrefix) == ["presence."])
            #expect(retractions.first?.except == [WorldFacts.personState])
        }

        let temperature = try #require(
            try reduce(
                HouseEvents.measurementChanged, driveway,
                ["predicate": .string("temperature_f"), "value": .number(68.3)]))
        #expect(temperature.predicate == "environment.temperature_f")
        #expect(temperature.value == .number(68.3))

        let offered = try #require(
            try reduce(HouseEvents.scenesOffered, house, ["scenes": .array([.string("Bedtime")])]))
        #expect(offered.predicate == WorldFacts.houseScenes)
        let requested = try #require(
            try reduce(HouseEvents.sceneRequested, house, ["scene": .string("Bedtime")]))
        #expect(requested.predicate == WorldFacts.houseSceneRequested)
        #expect(requested.validTo == now.addingTimeInterval(HouseReducer.requestLifetime))
        let activated = try #require(
            try reduce(HouseEvents.sceneActivated, house, ["scene": .string("Bedtime")]))
        #expect(activated.predicate == WorldFacts.houseScene)
        #expect(activated.value == .string("Bedtime"))

        #expect(
            try reducer.reduce(try event(HouseEvents.measurementChanged, driveway)).changedFacts
                .isEmpty)
    }

    private func event(
        _ type: WorldEventType, _ subject: EntityID, _ payload: [String: WorldJSONValue] = [:]
    )
        throws -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: type, occurredAt: now,
            source: EventSource(
                id: SourceID(validating: "home-assistant:test"), kind: "home-assistant"),
            subjectIDs: [subject],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: payload)
    }

    @Test("A media change is a fact on the room; going off ends it a second later")
    func mediaFacts() throws {
        let room = try EntityID(validating: "place:family-room")
        let when = Date(timeIntervalSince1970: 1_790_130_000)
        func changed(_ value: WorldJSONValue) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: HouseEvents.mediaChanged, occurredAt: when,
                source: EventSource(
                    id: try SourceID(
                        validating: "home-assistant:media-player-family-room-receiver"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [room], placeID: room,
                epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: ["predicate": .string("source"), "value": value])
        }
        let reducer = HouseReducer()
        let on = try #require(
            try reducer.reduce(try changed(.string("Apple TV, volume 40%"))).changedFacts.first)
        #expect(on.subjectID == room)
        #expect(on.predicate == "media.source")
        #expect(on.value == .string("Apple TV, volume 40%"))
        #expect(on.validTo == nil)
        let off = try #require(try reducer.reduce(try changed(.null)).changedFacts.first)
        #expect(off.value == .null)
        #expect(off.validTo == when.addingTimeInterval(1))
        // State, not story: a media change is never a happening.
        #expect(!Happening.isStoryworthy(HouseEvents.mediaChanged))
    }

}
