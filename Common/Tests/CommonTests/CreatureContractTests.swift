import Foundation
import Testing

@testable import Common

/// Creature configuration against the server 3.45.0 contract (console#87).
///
/// Two shapes matter, and they're the two fixtures here: a fully-populated Beaky — inputs,
/// `mouth_input`, gaze, and both animation-id lists — and an otherwise-minimal creature with
/// every optional absent. Between them they cover "carry everything faithfully" and "invent
/// nothing".
@Suite("Creature server contract")
struct CreatureContractTests {

    private let beakyId = "5d7c1a02-9b34-4e18-8f6a-2c0d3e5b7a91"

    /// A Beaky-shaped configuration, as the server would send it.
    private var beakyJSON: String {
        """
        {
          "id": "\(beakyId)",
          "name": "Beaky",
          "channel_offset": 0,
          "audio_channel": 1,
          "mouth_slot": 6,
          "inputs": [
            {"name": "neck_left",  "slot": 0, "width": 2, "joystick_axis": 0},
            {"name": "neck_right", "slot": 2, "width": 2, "joystick_axis": 1},
            {"name": "neck_rotate","slot": 4, "width": 2, "joystick_axis": 2},
            {"name": "beak",       "slot": 6, "width": 2, "joystick_axis": 3},
            {"name": "chest",      "slot": 8, "width": 2, "joystick_axis": 4},
            {"name": "stand_rotate","slot": 10, "width": 2, "joystick_axis": 5}
          ],
          "mouth_input": "beak",
          "speech_loop_animation_ids": [
            "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
            "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e"
          ],
          "idle_animation_ids": ["3c4d5e6f-7a8b-4c9d-0e1f-2a3b4c5d6e7f"],
          "gaze": {
            "pan": {
              "input": "neck_rotate",
              "degrees_at_min": -75.0,
              "degrees_at_max": 75.0,
              "listening_amount": 0.65
            },
            "elevation": {
              "input": "neck_left",
              "degrees_at_min": -20.0,
              "degrees_at_max": 35.0
            }
          }
        }
        """
    }

    /// The same creature with every optional gone — no mouth input, no loops, no gaze.
    private var minimalJSON: String {
        """
        {
          "id": "\(beakyId)",
          "name": "Spare Parts",
          "channel_offset": 32,
          "audio_channel": 4,
          "mouth_slot": 2,
          "inputs": []
        }
        """
    }

    private func decode(_ json: String) throws -> Creature {
        try JSONDecoder().decode(Creature.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    @Test("a Beaky-shaped config decodes every field")
    func beakyDecodes() throws {
        let beaky = try decode(beakyJSON)

        #expect(beaky.name == "Beaky")
        #expect(beaky.channelOffset == 0)
        #expect(beaky.audioChannel == 1)
        #expect(beaky.mouthSlot == 6)
        #expect(beaky.inputs.count == 6)
        #expect(beaky.mouthInput == "beak")
        #expect(beaky.speechLoopAnimationIds.count == 2)
        #expect(beaky.idleAnimationIds.count == 1)

        let gaze = try #require(beaky.gaze)
        #expect(gaze.pan?.input == "neck_rotate")
        #expect(gaze.pan?.degreesAtMin == -75)
        #expect(gaze.pan?.degreesAtMax == 75)
        #expect(gaze.pan?.listeningAmount == 0.65)
        #expect(gaze.pan?.isValid == true)
        // `listening_amount` was absent on this axis, and stays absent rather than becoming a
        // guessed default.
        #expect(gaze.elevation?.listeningAmount == nil)
        #expect(gaze.cock == nil)
        #expect(gaze.axes.map(\.name) == ["Pan", "Elevation"])
    }

    @Test("mouth_input resolves to the named input's slot")
    func mouthInputResolves() throws {
        let beaky = try decode(beakyJSON)
        #expect(beaky.resolvedMouthSlot == 6)

        // A creature with no override falls back to the raw slot number.
        let minimal = try decode(minimalJSON)
        #expect(minimal.mouthInput == nil)
        #expect(minimal.resolvedMouthSlot == minimal.mouthSlot)
    }

    @Test("a config with every optional absent decodes")
    func minimalDecodes() throws {
        let creature = try decode(minimalJSON)

        #expect(creature.inputs.isEmpty)
        #expect(creature.mouthInput == nil)
        #expect(creature.speechLoopAnimationIds.isEmpty)
        #expect(creature.idleAnimationIds.isEmpty)
        #expect(creature.gaze == nil)
        #expect(creature.runtime == nil)
    }

    /// An older oat++ response wrote `null` where 3.45.0 omits the key. Both have to mean the
    /// same thing, and neither may survive into what we send back.
    @Test("legacy null optionals decode as absent")
    func legacyNullsDecodeAsAbsent() throws {
        let json = """
            {
              "id": "\(beakyId)",
              "name": "Legacy",
              "channel_offset": 8,
              "audio_channel": 2,
              "mouth_slot": 3,
              "inputs": null,
              "mouth_input": null,
              "speech_loop_animation_ids": null,
              "idle_animation_ids": null,
              "gaze": null,
              "runtime": null
            }
            """
        let creature = try decode(json)

        #expect(creature.inputs.isEmpty)
        #expect(creature.mouthInput == nil)
        #expect(creature.speechLoopAnimationIds.isEmpty)
        #expect(creature.idleAnimationIds.isEmpty)
        #expect(creature.gaze == nil)

        try NeutralContract.expectNoNulls(
            creature.configurationPayload(), "a config normalized from legacy nulls")
    }

    /// An empty string is not an accepted stand-in for absent — the server's `optionalString`
    /// rejects one — so it must not come back out of the Console either.
    @Test("an empty mouth_input is treated as absent")
    func emptyMouthInputIsAbsent() throws {
        let json = minimalJSON.replacingOccurrences(
            of: "\"inputs\": []", with: "\"inputs\": [], \"mouth_input\": \"\"")
        let creature = try decode(json)

        #expect(creature.mouthInput == nil)
        let object = try NeutralContract.encodedObject(creature.configurationPayload())
        #expect(object["mouth_input"] == nil)
    }

    // MARK: Encoding

    @Test("a minimal config omits every absent optional")
    func minimalEncodingOmitsOptionals() throws {
        let creature = try decode(minimalJSON)
        let object = try NeutralContract.encodedObject(creature.configurationPayload())

        // Required fields are always present.
        #expect(object["id"] as? String == beakyId)
        #expect(object["name"] as? String == "Spare Parts")
        #expect(object["channel_offset"] as? Int == 32)
        #expect(object["audio_channel"] as? Int == 4)
        #expect(object["mouth_slot"] as? Int == 2)
        // `inputs` is preserved whenever configured, and an empty array is a real value here
        // rather than an absent one.
        #expect(object["inputs"] as? [Any] != nil)

        for absent in [
            "mouth_input", "speech_loop_animation_ids", "idle_animation_ids", "gaze",
        ] {
            #expect(object[absent] == nil, "\(absent) should have been omitted")
        }
        try NeutralContract.expectNoNulls(creature.configurationPayload(), "a minimal config")
    }

    @Test("a Beaky config encodes no nulls and no runtime")
    func beakyEncodingIsClean() throws {
        let beaky = try decode(beakyJSON)
        let object = try NeutralContract.encodedObject(beaky.configurationPayload())

        #expect(object["mouth_input"] as? String == "beak")
        #expect((object["speech_loop_animation_ids"] as? [Any])?.count == 2)
        #expect((object["idle_animation_ids"] as? [Any])?.count == 1)

        let gaze = try #require(object["gaze"] as? [String: Any])
        #expect(gaze["pan"] != nil)
        #expect(gaze["elevation"] != nil)
        // The axis that had no listening amount doesn't get one on the way out.
        let elevation = try #require(gaze["elevation"] as? [String: Any])
        #expect(elevation["listening_amount"] == nil)
        // The cock axis was never configured, so it isn't in the object at all.
        #expect(gaze["cock"] == nil)

        // `runtime` is the server's view of what the creature is doing. A config write never
        // asserts it.
        #expect(object["runtime"] == nil)

        try NeutralContract.expectNoNulls(beaky.configurationPayload(), "a Beaky config")
    }

    @Test("round-tripping a Beaky config preserves its meaning")
    func beakyRoundTrips() throws {
        let original = try decode(beakyJSON)
        let data = try JSONEncoder().encode(original.configurationPayload())
        let decoded = try JSONDecoder().decode(Creature.self, from: data)

        #expect(decoded == original)
    }

    /// A creature read from the server carries `runtime`; editing and posting it back must not
    /// send that block, but the round trip must otherwise be lossless.
    @Test("a config read with runtime posts back without it")
    func runtimeIsNotEchoedBack() throws {
        let withRuntime = beakyJSON.replacingOccurrences(
            of: "\"mouth_input\": \"beak\",",
            with: "\"mouth_input\": \"beak\", \"runtime\": {\"idle_enabled\": true},")
        let creature = try decode(withRuntime)
        #expect(creature.runtime?.idleEnabled == true)

        let object = try NeutralContract.encodedObject(creature.configurationPayload())
        #expect(object["runtime"] == nil)
        #expect(object["mouth_input"] as? String == "beak")
    }

    @Test("an empty gaze object decodes as no gaze at all")
    func emptyGazeIsNoGaze() throws {
        let json = minimalJSON.replacingOccurrences(
            of: "\"inputs\": []", with: "\"inputs\": [], \"gaze\": {}")
        let creature = try decode(json)

        #expect(creature.gaze == nil)
        let object = try NeutralContract.encodedObject(creature.configurationPayload())
        #expect(object["gaze"] == nil)
    }

    @Test("a gaze axis with a zero-width range is not valid")
    func zeroWidthGazeAxisIsInvalid() {
        let flat = GazeAxis(input: "neck_rotate", degreesAtMin: 40, degreesAtMax: 40)
        #expect(!flat.isValid)

        let outOfRange = GazeAxis(
            input: "neck_rotate", degreesAtMin: -40, degreesAtMax: 40, listeningAmount: 1.5)
        #expect(!outOfRange.isValid)

        let good = GazeAxis(
            input: "neck_rotate", degreesAtMin: -40, degreesAtMax: 40, listeningAmount: 0.5)
        #expect(good.isValid)
    }
}
