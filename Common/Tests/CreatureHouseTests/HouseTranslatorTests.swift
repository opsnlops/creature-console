import Foundation
import Testing
import WorldCore

@testable import creature_house

@Suite("The house, translated")
struct HouseTranslatorTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let translator = HouseTranslator(mappings: [
        EntityMapping(
            entityID: "lock.front_door", subjectID: try! EntityID(validating: "place:front-door"),
            kind: .lock),
        EntityMapping(
            entityID: "binary_sensor.entryway_motion",
            subjectID: try! EntityID(validating: "place:entryway"), kind: .motion),
        EntityMapping(
            entityID: "person.april", subjectID: try! EntityID(validating: "person:april"),
            kind: .person),
        EntityMapping(
            entityID: "sensor.outside_temperature",
            subjectID: try! EntityID(validating: "place:outside"), kind: .measurement,
            predicate: "temperature_f", minimumChange: 1),
        EntityMapping(
            entityID: "binary_sensor.driveway_vehicle_detected",
            subjectID: try! EntityID(validating: "place:driveway"), kind: .detection,
            detects: .vehicle),
    ])

    @Test("A lock unlocking is a door event about the place, keyed by Home Assistant's context")
    func lockBecomesDoorEvent() throws {
        let events = try translator.events(
            from: state("lock.front_door", "locked"),
            to: state("lock.front_door", "unlocked", context: "01J8ABC"))

        let event = try #require(events.only)
        #expect(event.type == HouseEvents.doorUnlocked)
        #expect(event.subjectIDs == [try EntityID(validating: "place:front-door")])
        #expect(event.placeID?.rawValue == "place:front-door")
        #expect(event.source.id.rawValue == "home-assistant:lock-front-door")
        #expect(event.source.kind == "home-assistant")
        #expect(event.source.sourceEventID == "context:01J8ABC")
        #expect(event.occurredAt == now)
        #expect(event.payload["previous_state"] == .string("locked"))
        #expect(event.epistemic.type == .observed)
    }

    @Test("Unmapped entities, unchanged states, and dead devices are not news")
    func quietCases() throws {
        #expect(try translator.events(from: nil, to: state("light.kitchen", "on")).isEmpty)
        #expect(
            try translator.events(
                from: state("lock.front_door", "locked"), to: state("lock.front_door", "locked")
            ).isEmpty)
        #expect(
            try translator.events(from: nil, to: state("lock.front_door", "unavailable")).isEmpty)
        #expect(try translator.events(from: nil, to: state("lock.front_door", "jammed")).isEmpty)
    }

    @Test("At startup every mapped state is announced once, keyed by when it last changed")
    func snapshotIsIdempotent() throws {
        let first = try translator.events(from: nil, to: state("lock.front_door", "locked"))
        let again = try translator.events(from: nil, to: state("lock.front_door", "locked"))
        #expect(first.only?.type == HouseEvents.doorLocked)
        #expect(first.only?.source.sourceEventID == again.only?.source.sourceEventID)
        #expect(first.only?.source.sourceEventID?.hasPrefix("snapshot:") == true)
    }

    @Test("Motion and people: on/off, home/away")
    func motionAndPeople() throws {
        #expect(
            try translator.events(
                from: state("binary_sensor.entryway_motion", "off"),
                to: state("binary_sensor.entryway_motion", "on")
            ).only?.type == HouseEvents.motionDetected)
        #expect(
            try translator.events(
                from: state("person.april", "home"), to: state("person.april", "not_home")
            ).only?.type == HouseEvents.personLeft)
        #expect(
            try translator.events(
                from: state("person.april", "Work"), to: state("person.april", "home")
            ).only?.type == HouseEvents.personArrived)
        // Moving between two away zones is not an arrival or a departure.
        #expect(
            try translator.events(
                from: state("person.april", "Work"), to: state("person.april", "not_home")
            ).isEmpty)
    }

    @Test("A measurement carries its predicate and value; small wobbles are dropped")
    func measurements() throws {
        let events = try translator.events(
            from: state("sensor.outside_temperature", "68.3"),
            to: state(
                "sensor.outside_temperature", "69.5",
                attributes: ["unit_of_measurement": .string("°F")]))
        let event = try #require(events.only)
        #expect(event.type == HouseEvents.measurementChanged)
        #expect(event.payload["predicate"] == .string("temperature_f"))
        #expect(event.payload["value"] == .number(69.5))
        #expect(event.payload["unit"] == .string("°F"))
        #expect(
            try translator.events(
                from: state("sensor.outside_temperature", "68.3"),
                to: state("sensor.outside_temperature", "68.9")
            ).isEmpty)
        #expect(
            try translator.events(from: nil, to: state("sensor.outside_temperature", "unknown"))
                .isEmpty)
    }

    @Test("A creeping thermometer crosses minimum_change cumulatively, measured from what was told")
    func minimumChangeIsCumulative() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        // The snapshot is always told.
        let first = try await announcer.events(
            from: nil, to: state("sensor.outside_temperature", "68.7"))
        #expect(first.only?.payload["value"] == .number(68.7))
        // 0.2° steps: none is news on its own…
        #expect(
            try await announcer.events(
                from: state("sensor.outside_temperature", "68.7"),
                to: state("sensor.outside_temperature", "68.9")
            ).isEmpty)
        #expect(
            try await announcer.events(
                from: state("sensor.outside_temperature", "68.9"),
                to: state("sensor.outside_temperature", "69.4")
            ).isEmpty)
        // …until the drift from 68.7 reaches a degree.
        let crossed = try await announcer.events(
            from: state("sensor.outside_temperature", "69.4"),
            to: state("sensor.outside_temperature", "70.1"))
        #expect(crossed.only?.payload["value"] == .number(70.1))
        // And the next degree is measured from 70.1.
        #expect(
            try await announcer.events(
                from: state("sensor.outside_temperature", "70.1"),
                to: state("sensor.outside_temperature", "70.6")
            ).isEmpty)
    }

    @Test("A camera detection is a moment: only turning on, and never at startup")
    func detections() throws {
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "off"),
                to: state("binary_sensor.driveway_vehicle_detected", "on")
            ).only?.type == HouseEvents.vehicleSeen)
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "on"),
                to: state("binary_sensor.driveway_vehicle_detected", "off")
            ).isEmpty)
        #expect(
            try translator.events(
                from: nil, to: state("binary_sensor.driveway_vehicle_detected", "on")
            )
            .isEmpty)
    }

    private func state(
        _ entityID: String, _ state: String, attributes: [String: WorldJSONValue] = [:],
        context: String? = nil
    ) -> EntityState {
        EntityState(
            entityID: entityID, state: state, attributes: attributes, lastChanged: now,
            contextID: context)
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
