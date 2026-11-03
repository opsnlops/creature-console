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

        // Quiet hours are the house's, not April's: they live only in the opening policy, so a
        // scene April starts by speaking is never gated by them. (The conversation path has no
        // quiet-hours check at all; this pins the design.)
        #expect(SceneLimits(quietHours: quiet).quietHours?.contains(lateNight) == true)

        let json = """
            {"quiet_hours": {"from": "23:00", "to": "07:00"}}
            """
        let limits = try JSONDecoder().decode(SceneLimits.self, from: Data(json.utf8))
        #expect(limits.quietHours == quiet)
        #expect(SceneLimits().quietHours == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                SceneLimits.self,
                from: Data("{\"quiet_hours\": {\"from\": \"25:00\", \"to\": \"07:00\"}}".utf8))
        }
    }

    @Test(
        "The house may ask instead of tell: consider_on occasions, open_on winning when both match")
    func considerOccasions() async throws {
        let kitchen = try EntityID(validating: "place:kitchen")
        let policy = SceneOpeningPolicy(
            rules: [SceneOpeningRule(event: HouseEvents.personSeen, places: [driveway])],
            considerRules: [
                SceneOpeningRule(event: HouseEvents.motionDetected, cooldownSeconds: 600),
                SceneOpeningRule(event: HouseEvents.personSeen, cooldownSeconds: 300),
            ])
        // Motion is a question for the lead.
        let motion = try event(HouseEvents.motionDetected, kitchen)
        let asked = try #require(await policy.occasion(for: motion, at: now))
        #expect(asked == SceneOpeningPolicy.Occasion(place: kitchen, kind: .houseConsideration))
        await policy.opened(asked, for: motion, at: now)
        // A person in the driveway is a must-speak, even though a consider rule also matches.
        #expect(
            await policy.occasion(for: try event(HouseEvents.personSeen, driveway), at: now)
                == SceneOpeningPolicy.Occasion(place: driveway, kind: .worldEvent))
        // A person in the kitchen is only a question.
        #expect(
            await policy.occasion(for: try event(HouseEvents.personSeen, kitchen), at: now)
                == SceneOpeningPolicy.Occasion(place: kitchen, kind: .houseConsideration))
        // Questions have their own cooldown.
        #expect(
            await policy.occasion(for: try event(HouseEvents.motionDetected, kitchen), at: now + 60)
                == nil)
        #expect(
            await policy.occasion(
                for: try event(HouseEvents.motionDetected, kitchen), at: now + 601)
                != nil)
        let json = """
            {"consider_on": [{"event": "motion.detected", "cooldown_seconds": 600}]}
            """
        let limits = try JSONDecoder().decode(SceneLimits.self, from: Data(json.utf8))
        #expect(limits.considerOn.count == 1)
        #expect(limits.openOn.isEmpty)
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
        let outside = try EntityID(validating: "place:outside")
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.dusk, outside, payload: ["lux": .number(84.6)]),
                place: outside, household: HouseholdSituation(aprilHome: true))
                == "Dusk is falling outside. The daylight outside is down to about 85 lux. April is home."
        )
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.dawn, outside, payload: ["lux": .number(130)]),
                place: outside)
                == "Dawn is breaking outside. The daylight outside is up to about 130 lux.")
    }

    @Test("The house says who a camera saw: April lives alone, so at home it is her")
    func stageNoteNamesApril() throws {
        let seen = try event(HouseEvents.personSeen, driveway)
        let home = HouseholdSituation(aprilHome: true)
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: home)
                == "A person was just seen at the driveway. April is home and lives alone, so it is most likely her."
        )
        let away = HouseholdSituation(aprilHome: false)
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: away)
                == "A person was just seen at the driveway. April is away, so it is somebody else.")
        let company = HouseholdSituation(aprilHome: true, visitorExpected: "Tamara, for cleaning")
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: company)
                == "A person was just seen at the driveway. April is home, and a visitor is expected - Tamara, for cleaning - so it is either her or them."
        )
        // A delivery on its way today: the driver is the other person it could be.
        let parcel = HouseholdSituation(aprilHome: true, deliveryExpected: "Amazon: Hardware")
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: parcel)
                == "A person was just seen at the driveway. April is home, and a delivery is expected - Amazon: Hardware - so it is either her or the driver."
        )
        let both = HouseholdSituation(
            aprilHome: true, visitorExpected: "Tamara, for cleaning",
            deliveryExpected: "Amazon: Hardware")
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: both)
                == "A person was just seen at the driveway. April is home, and a visitor is expected - Tamara, for cleaning - and a delivery - Amazon: Hardware - so it is her, them, or the driver."
        )
        let awayParcel = HouseholdSituation(aprilHome: false, deliveryExpected: "Amazon: Hardware")
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway, household: awayParcel)
                == "A person was just seen at the driveway. April is away; a delivery is expected - Amazon: Hardware - so it is probably the driver."
        )
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.vehicleSeen, driveway), place: driveway,
                household: parcel)
                == "A vehicle was just seen at the driveway. April is home; a delivery is expected - Amazon: Hardware."
        )
        let gone = try event(
            HouseEvents.personGone, driveway, payload: ["after_seconds": .number(1_500)])
        #expect(
            SceneOpeningPolicy.triggerText(for: gone, place: driveway, household: home)
                == "A person who had been at the driveway for 25 minutes is no longer seen there. April is home and lives alone, so it was most likely her."
        )
        // A vehicle could be hers or a delivery's: only where she is.
        #expect(
            SceneOpeningPolicy.triggerText(
                for: try event(HouseEvents.vehicleSeen, driveway), place: driveway,
                household: away)
                == "A vehicle was just seen at the driveway. April is away.")
        // Nothing known, nothing claimed.
        #expect(
            SceneOpeningPolicy.triggerText(for: seen, place: driveway)
                == "A person was just seen at the driveway.")
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

    @Test("Telemetry is a fact, never a story: a body's power rail is not a happening")
    func telemetryIsNotStory() throws {
        let rail = try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"), occurredAt: now,
            source: EventSource(id: SourceID(validating: "body:sensors"), kind: "body"),
            subjectIDs: [try EntityID(validating: "character:mango")],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["predicate": .string("body.power")])
        #expect(Happening.isStoryworthy(rail.type))
        #expect(!Happening.isStoryworthy(rail))
        let told = try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"), occurredAt: now,
            source: EventSource(id: SourceID(validating: "bridge:mail"), kind: "bridge"),
            subjectIDs: [driveway], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["predicate": .string("visitor.expected")])
        #expect(Happening.isStoryworthy(told))
    }

    @Test("An occasion held back spends nothing: the next score may still ask (#271)")
    func heldBackSpendsNothing() async throws {
        let seahawks = try EntityID(validating: "team:seahawks")
        let policy = SceneOpeningPolicy(
            rules: [],
            considerRules: [SceneOpeningRule(event: HouseEvents.gameScored, cooldownSeconds: 180)],
            gapSeconds: 60)
        // The Bears' touchdown came as April started talking: the opener held it back and
        // opened nothing.
        let touchdown = try event(HouseEvents.gameScored, seahawks)
        #expect(await policy.occasion(for: touchdown, at: now) != nil)
        // The extra point, once her scene had closed, is asked about - and that one is spent.
        let extraPoint = try event(HouseEvents.gameScored, seahawks)
        let asked = try #require(await policy.occasion(for: extraPoint, at: now + 31))
        await policy.opened(asked, for: extraPoint, at: now + 31)
        #expect(await policy.occasion(for: touchdown, at: now + 90) == nil)
        #expect(await policy.occasion(for: touchdown, at: now + 212) != nil)
    }

    @Test("The house's cast is everyone in the room, shuffled: nobody is always fourth (#274)")
    func castIsShuffled() throws {
        let birds = try ["beaky", "mango", "caroll", "kenny"].map {
            try EntityID(validating: "character:\($0)")
        }
        var dice = Dice(seed: 274)
        var spoke: [EntityID: Int] = [:]
        for _ in 0..<200 {
            let cast = SceneOpeningPolicy.cast(birds, using: &dice)
            #expect(Set(cast) == Set(birds))
            #expect(cast.count == birds.count)
            // The three a house scene's turns reach.
            for bird in cast.prefix(3) { spoke[bird, default: 0] += 1 }
        }
        // Kenny, last to log in, speaks about as often as anyone.
        for bird in birds { #expect(spoke[bird, default: 0] > 100) }
    }

    @Test("An ending is an occasion wherever its beginning is, and reads as a stay")
    func endingsFollowBeginnings() async throws {
        let policy = SceneOpeningPolicy(
            rules: [SceneOpeningRule(event: HouseEvents.vehicleSeen, places: [driveway])])
        let gone = try event(
            HouseEvents.vehicleGone, driveway, payload: ["after_seconds": .number(7_800)])
        #expect(
            await policy.occasion(for: gone, at: now)
                == SceneOpeningPolicy.Occasion(place: driveway, kind: .worldEvent))
        #expect(
            SceneOpeningPolicy.triggerText(for: gone, place: driveway)
                == "A vehicle that had been at the driveway for 2 hours and 10 minutes has gone.")
        let brief = try event(
            HouseEvents.personGone, driveway, payload: ["after_seconds": .number(1_500)])
        #expect(
            SceneOpeningPolicy.triggerText(for: brief, place: driveway)
                == "A person who had been at the driveway for 25 minutes is no longer seen there.")
        // Nowhere a vehicle is watched for, nothing.
        let elsewhere = try EntityID(validating: "place:kitchen")
        #expect(
            await policy.occasion(for: try event(HouseEvents.vehicleGone, elsewhere), at: now)
                == nil)
    }

    @Test(
        "A score is the house asking, once in three minutes: the touchdown, not its extra point (#269)"
    )
    func scoresAreConsidered() async throws {
        let seahawks = try EntityID(validating: "team:seahawks")
        let policy = SceneOpeningPolicy(
            rules: [],
            considerRules: [
                SceneOpeningRule(event: HouseEvents.gameScored, cooldownSeconds: 180),
                SceneOpeningRule(event: HouseEvents.gameScoreCorrected, cooldownSeconds: 180),
            ])
        let touchdown = try event(HouseEvents.gameScored, seahawks)
        let asked = try #require(await policy.occasion(for: touchdown, at: now))
        #expect(asked == .init(place: seahawks, kind: .houseConsideration))
        await policy.opened(asked, for: touchdown, at: now)
        // The extra point a minute later is the same remark.
        #expect(await policy.occasion(for: touchdown, at: now + 60) == nil)
        // Taken back on review: a question of its own.
        #expect(
            await policy.occasion(
                for: try event(HouseEvents.gameScoreCorrected, seahawks), at: now + 90) != nil)
        #expect(await policy.occasion(for: touchdown, at: now + 240) != nil)
        // The rest of a game asks nobody.
        for type in [HouseEvents.gameStarted, HouseEvents.gameFinal, HouseEvents.gameScheduled] {
            #expect(await policy.occasion(for: try event(type, seahawks), at: now + 600) == nil)
        }
    }

    @Test("A score in words the birds can use: who scored on whom, the score, the clock, the play")
    func scoreTriggerText() throws {
        let seahawks = try EntityID(validating: "team:seahawks")
        let home = HouseholdSituation(aprilHome: true)
        var payload: [String: WorldJSONValue] = [
            "team": .string("Seattle Seahawks"), "opponent": .string("Chicago Bears"),
            "team_score": .number(14), "opponent_score": .number(7),
            "clock": .string("7:12 - 2nd"), "scored_by": .string("Seattle Seahawks"),
            "last_play": .string("J. Smith 12 Yd Run (K. Jones Kick)"),
        ]
        func said(_ type: WorldEventType) throws -> String {
            SceneOpeningPolicy.triggerText(
                for: try event(type, seahawks, payload: payload), place: seahawks, household: home)
        }
        let score =
            "Seattle Seahawks 14, Chicago Bears 7 (7:12 - 2nd). The play: J. Smith 12 Yd Run (K. Jones Kick). April is home."
        #expect(
            try said(HouseEvents.gameScored)
                == "Seattle Seahawks, the team April follows, just scored against Chicago Bears: "
                + score)
        payload["scored_by"] = .string("Chicago Bears")
        #expect(
            try said(HouseEvents.gameScored)
                == "Chicago Bears just scored against Seattle Seahawks, the team April follows: "
                + score)
        payload["scored_by"] = nil
        #expect(
            try said(HouseEvents.gameScored)
                == "Both sides scored in the game between Seattle Seahawks, the team April follows, and Chicago Bears: "
                + score)
        #expect(
            try said(HouseEvents.gameScoreCorrected)
                == "Points just came off the board in the game between Seattle Seahawks, the team April follows, and Chicago Bears - a score taken back. It now stands: "
                + score)
        // The ball changing hands, with where it is now.
        payload["possession"] = .string("Chicago Bears")
        payload["down_distance"] = .string("1st & 10 at CHI 25")
        payload["last_play"] = .string("D. Moore punts 44 yards.")
        #expect(
            try said(HouseEvents.gamePossession)
                == "The ball just went to Chicago Bears in the game between Seattle Seahawks, the team April follows, and Chicago Bears: Seattle Seahawks 14, Chicago Bears 7 (7:12 - 2nd; 1st & 10 at CHI 25). The play: D. Moore punts 44 yards. April is home."
        )
    }

    private func event(
        _ type: WorldEventType, _ subject: EntityID, payload: [String: WorldJSONValue] = [:]
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: type, occurredAt: now,
            source: EventSource(
                id: SourceID(validating: "home-assistant:test"), kind: "home-assistant"),
            subjectIDs: [subject], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: payload)
    }
}

/// A seeded generator, so a shuffle in a test is the same every run (SplitMix64).
private struct Dice: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
