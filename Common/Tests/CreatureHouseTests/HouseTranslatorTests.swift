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

    @Test("The house tells the world which places its cameras watch, once per place")
    func camerasAnnounceThemselves() throws {
        let place = try EntityID(validating: "place:driveway")
        let first = try HouseService.cameraWatching(place)
        let again = try HouseService.cameraWatching(place)
        #expect(first.type == HouseEvents.cameraWatching)
        #expect(first.subjectIDs == [place])
        #expect(first.placeID == place)
        #expect(first.source.sourceEventID == "watching:place:driveway")
        #expect(first.source.sourceEventID == again.source.sourceEventID)
    }

    @Test("A camera detection is a moment: only turning on, and never at startup")
    func detections() throws {
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "off"),
                to: state("binary_sensor.driveway_vehicle_detected", "on")
            ).only?.type == HouseEvents.vehicleSeen)
        // A car that passed: turning off a minute later is nothing twice.
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "on"),
                to: state("binary_sensor.driveway_vehicle_detected", "off", at: now + 60)
            ).isEmpty)
        #expect(
            try translator.events(
                from: nil, to: state("binary_sensor.driveway_vehicle_detected", "on")
            )
            .isEmpty)
    }

    @Test("A sighting that lasted is news when it ends: the cleaners leaving")
    func longSightingsEnd() throws {
        // The cleaners' car sat in the driveway for two hours, then went.
        let gone = try translator.events(
            from: state("binary_sensor.driveway_vehicle_detected", "on"),
            to: state("binary_sensor.driveway_vehicle_detected", "off", at: now + 2 * 3_600)
        ).only
        #expect(gone?.type == HouseEvents.vehicleGone)
        #expect(gone?.payload["after_seconds"] == .number(7_200))
        #expect(gone?.subjectIDs.first?.rawValue == "place:driveway")
        // Exactly the threshold counts; a second less does not.
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "on"),
                to: state("binary_sensor.driveway_vehicle_detected", "off", at: now + 600)
            ).only?.type == HouseEvents.vehicleGone)
        #expect(
            try translator.events(
                from: state("binary_sensor.driveway_vehicle_detected", "on"),
                to: state("binary_sensor.driveway_vehicle_detected", "off", at: now + 599)
            ).isEmpty)
    }

    private func state(
        _ entityID: String, _ state: String, attributes: [String: WorldJSONValue] = [:],
        context: String? = nil, at changed: Date? = nil
    ) -> EntityState {
        EntityState(
            entityID: entityID, state: state, attributes: attributes, lastChanged: changed ?? now,
            contextID: context)
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? self[0] : nil }
}

@Suite("The TV, translated")
struct HouseMediaTests {
    private let now = Date(timeIntervalSince1970: 1_790_130_000)
    private let familyRoom = try! EntityID(validating: "place:family-room")

    private func state(
        _ entity: String, _ value: String, _ attributes: [String: WorldJSONValue] = [:],
        at offset: TimeInterval = 0
    ) -> EntityState {
        EntityState(
            entityID: entity, state: value, attributes: attributes,
            lastChanged: now.addingTimeInterval(offset), contextID: "ctx-\(entity)-\(offset)")
    }

    @Test("What April's players said on 2026-09-22, in words the birds can use")
    func realShapes() {
        // As Home Assistant reported them, YouTube on the Apple TV through the receiver.
        #expect(
            HouseTranslator.mediaWords(
                state(
                    "media_player.family_room_tv_samsung", "on",
                    [
                        "friendly_name": .string("Family Room TV Samsung"),
                        "device_class": .string("tv"),
                        "is_volume_muted": .bool(false),
                    ])) == "on")
        #expect(
            HouseTranslator.mediaWords(
                state(
                    "media_player.family_room_receiver", "on",
                    [
                        "device_class": .string("receiver"), "media_title": .string("Apple TV"),
                        "media_content_type": .string("channel"), "volume_level": .number(0.4),
                        "source": .string("Apple TV"),
                    ])) == "Apple TV, volume 40%")
        // Idle with a title left over from last time is not playing.
        #expect(
            HouseTranslator.mediaWords(
                state(
                    "media_player.bunnys_bathroom", "idle",
                    [
                        "app_name": .string("AirMusic"),
                        "media_title": .string("The Valkyrie (UpOnly 634) [Mix Cut] {MIXED}"),
                        "media_artist": .string("Focusing"),
                    ])) == nil)
        #expect(
            HouseTranslator.mediaWords(state("media_player.family_room_tv_direct", "unavailable"))
                == nil)
        // The Apple TV, once April adds the integration: app, title, paused.
        #expect(
            HouseTranslator.mediaWords(
                state(
                    "media_player.family_room_apple_tv", "paused",
                    [
                        "app_name": .string("YouTube"),
                        "media_title": .string("Building a Robot Parrot"),
                    ]))
                == "YouTube: Building a Robot Parrot (paused)")
        #expect(
            HouseTranslator.mediaWords(
                state(
                    "media_player.family_room_apple_tv", "playing",
                    [
                        "app_name": .string("Music"), "media_title": .string("Enchanted Tiki Room"),
                        "media_artist": .string("Disneyland"),
                    ]))
                == "Music: Enchanted Tiki Room by Disneyland")
    }

    @Test("A change in the words is news; the same words are not; going off ends the fact")
    func changes() throws {
        let translator = HouseTranslator(mappings: [
            EntityMapping(
                entityID: "media_player.family_room_tv_samsung", subjectID: familyRoom,
                kind: .media, predicate: "tv")
        ])
        // Startup, on: the fact.
        let on = try #require(
            try translator.events(from: nil, to: state("media_player.family_room_tv_samsung", "on"))
                .only)
        #expect(on.type == HouseEvents.mediaChanged)
        #expect(on.subjectIDs == [familyRoom])
        #expect(on.payload["predicate"] == .string("tv"))
        #expect(on.payload["value"] == .string("on"))
        // Startup, off: still said, so a stale "on" from before a restart is ended.
        let startOff = try #require(
            try translator.events(
                from: nil, to: state("media_player.family_room_tv_samsung", "off")
            ).only)
        #expect(startOff.payload["value"] == .null)
        // The same words: nothing.
        #expect(
            try translator.events(
                from: state("media_player.family_room_tv_samsung", "on"),
                to: state("media_player.family_room_tv_samsung", "on", at: 60)
            ).isEmpty)
        // Off, or gone: the fact ends.
        for gone in ["off", "standby", "unavailable"] {
            let event = try #require(
                try translator.events(
                    from: state("media_player.family_room_tv_samsung", "on"),
                    to: state("media_player.family_room_tv_samsung", gone, at: 60)
                ).only)
            #expect(event.payload["value"] == .null)
        }
    }
}
