import Foundation
import Testing
import WorldCore

@Suite("The house opens scenes")
struct SceneOpeningTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let driveway = try! EntityID(validating: "place:driveway")
    private let orchard = try! EntityID(validating: "place:orchard")
    private let frontDoor = try! EntityID(validating: "place:front-door")

    @Test("A matching event opens a scene once per cooldown, per place")
    func cooldownPerPlace() async throws {
        let policy = SceneOpeningPolicy(
            rules: [
                SceneOpeningRule(
                    event: HouseEvents.personSeen, places: [driveway, frontDoor],
                    cooldownSeconds: 300),
                SceneOpeningRule(event: HouseEvents.doorUnlocked, cooldownSeconds: 60),
            ], gapSeconds: 0)

        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: now)
                == driveway)
        // Again, too soon.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: now + 30)
                == nil)
        // A different place is its own cooldown.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, frontDoor), at: now + 30)
                == frontDoor)
        // A place the rule does not name.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, orchard), at: now + 30)
                == nil)
        // An event no rule names.
        #expect(
            await policy.shouldOpen(
                for: try event(HouseEvents.motionDetected, driveway), at: now + 30) == nil)
        // Any place, when the rule names none.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.doorUnlocked, frontDoor), at: now)
                == frontDoor)
        // After the cooldown.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: now + 301)
                == driveway)
    }

    @Test("A gap, when set, holds between any two scenes the house opens")
    func gapBetweenHouseScenes() async throws {
        let policy = SceneOpeningPolicy(
            rules: [
                SceneOpeningRule(event: HouseEvents.personSeen, cooldownSeconds: 300),
                SceneOpeningRule(event: HouseEvents.doorUnlocked, cooldownSeconds: 60),
            ], gapSeconds: 90)
        // The front door, then its camera, then the driveway's, in forty seconds.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.doorUnlocked, frontDoor), at: now)
                == frontDoor)
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, frontDoor), at: now + 13)
                == nil)
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: now + 27)
                == nil)
        // A minute and a half on, the house may speak again.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: now + 91)
                == driveway)
        // Off unless April asks for a quieter house.
        #expect(SceneLimits().houseGapSeconds == 0)
    }

    @Test("The birds sleep: nothing the house sees in quiet hours opens a scene")
    func quietHours() async throws {
        let quiet = QuietHours(from: "23:00", to: "07:00", timeZone: "America/Los_Angeles")
        // 2026-09-13 06:10 UTC is 11:10 PM Pacific on the 12th; 14:10 UTC is 7:10 AM.
        let lateNight = Date(timeIntervalSince1970: 1_789_193_400)
        let morning = Date(timeIntervalSince1970: 1_789_222_200)
        #expect(quiet.contains(lateNight))
        #expect(!quiet.contains(morning))
        #expect(quiet.contains(lateNight.addingTimeInterval(4 * 3_600)))  // 3:10 AM
        #expect(!QuietHours(from: "09:00", to: "17:00").contains(lateNight))

        let policy = SceneOpeningPolicy(
            rules: [SceneOpeningRule(event: HouseEvents.personSeen, cooldownSeconds: 300)],
            quietHours: quiet)
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: lateNight)
                == nil)
        // The first thing after seven may speak: the night touched no cooldown.
        #expect(
            await policy.shouldOpen(for: try event(HouseEvents.personSeen, driveway), at: morning)
                == driveway)

        let json = """
            {"quiet_hours": {"from": "23:00", "to": "07:00"}}
            """
        let limits = try JSONDecoder().decode(SceneLimits.self, from: Data(json.utf8))
        #expect(limits.quietHours == quiet)
        #expect(SceneLimits().quietHours == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                SceneLimits.self, from: Data("{\"quiet_hours\": {\"from\": \"25:00\", \"to\": \"07:00\"}}".utf8))
        }
    }

    @Test("The stage note the birds read is a plain sentence")
    func triggerText() throws {
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.personSeen, driveway), place: driveway)
                == "A person was just seen at the driveway.")
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.doorUnlocked, frontDoor), place: frontDoor)
                == "The front door was just unlocked.")
        let april = try EntityID(validating: "person:april")
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.personArrived, april), place: april)
                == "April just came home.")
    }

    @Test("Rules decode from world.json with sensible defaults")
    func rulesDecode() throws {
        let json = """
            { "floor_seconds": 8, "open_on": [
                { "event": "camera.person_seen", "places": ["place:driveway"], "cooldown_seconds": 120 },
                { "event": "door.unlocked" }
            ] }
            """
        let limits = try WorldJSON.makeDecoder().decode(SceneLimits.self, from: Data(json.utf8))
        #expect(limits.openOn.count == 2)
        #expect(limits.openOn[0].places == [driveway])
        #expect(limits.openOn[0].cooldownSeconds == 120)
        #expect(limits.openOn[1].places.isEmpty)
        #expect(limits.openOn[1].cooldownSeconds == 300)
        #expect(
            try WorldJSON.makeDecoder().decode(SceneLimits.self, from: Data("{}".utf8)).openOn
                .isEmpty)
    }

    private func event(_ type: WorldEventType, _ subject: EntityID) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: type, occurredAt: now,
            source: EventSource(
                id: SourceID(validating: "home-assistant:test"), kind: "home-assistant"),
            subjectIDs: [subject], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:])
    }
}
