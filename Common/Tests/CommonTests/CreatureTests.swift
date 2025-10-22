import Foundation
import Testing

@testable import Common

@Suite("Creature model tests")
struct CreatureTests {

    // MARK: Initialization
    @Test("initialization sets all properties correctly")
    func initialization() throws {
        let inputs: [Input] = [
            Input(name: "Left_Eye", slot: 1, width: 1, joystickAxis: 0),
            Input(name: "Right_Eye", slot: 2, width: 1, joystickAxis: 1),
        ]
        let creature = Creature(
            id: UUID().uuidString,
            name: "Bunny",
            channelOffset: 3,
            mouthSlot: 1,
            audioChannel: 2,
            inputs: inputs,
            realData: true
        )
        #expect(creature.name == "Bunny")
        #expect(creature.channelOffset == 3)
        #expect(creature.mouthSlot == 1)
        #expect(creature.audioChannel == 2)
        #expect(creature.realData == true)
        #expect(creature.inputs == inputs)
    }

    // MARK: Mock
    @Test("mock produces sensible values and inputs")
    func mockProducesSensibleValues() throws {
        let c = Creature.mock()
        #expect(!c.id.isEmpty)
        #expect(c.name == "MockCreature")
        #expect(c.inputs.count >= 2)
        #expect(c.mouthSlot == 2)
        #expect(c.inputs[0].name == "MockInput")
        #expect(c.inputs[0].slot == 1)
        #expect(c.inputs[0].width == 1)
        #expect(c.inputs[0].joystickAxis == 1)
    }

    // MARK: Codable
    @Test("Codable round-trip preserves value")
    func codableRoundTrip() throws {
        let inputs: [Input] = [
            Input(name: "MockInput", slot: 1, width: 1, joystickAxis: 1),
            Input(name: "Input 2", slot: 2, width: 2, joystickAxis: 2),
        ]
        let original = Creature(
            id: UUID().uuidString,
            name: "Marble",
            channelOffset: 7,
            mouthSlot: 3,
            audioChannel: 5,
            inputs: inputs,
            realData: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Creature.self, from: data)
        #expect(decoded == original)
    }

    @Test("Encoding uses expected snake_case keys")
    func encodingUsesSnakeCaseKeys() throws {
        let creature = Creature(
            id: UUID().uuidString,
            name: "Keys",
            channelOffset: 10,
            mouthSlot: 4,
            audioChannel: 3,
            inputs: [],
            realData: false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(creature)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["channel_offset"] as? Int == 10)
        #expect(object["mouth_slot"] as? Int == 4)
        #expect(object["audio_channel"] as? Int == 3)
        #expect(object["inputs"] != nil)
        #expect(object["channelOffset"] == nil)
        #expect(object["mouthSlot"] == nil)
        #expect(object["audioChannel"] == nil)
    }

    @Test("Decoding defaults realData to false when missing")
    func decodingDefaultsRealData() throws {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "name": "NoFlag",
            "channel_offset": 1,
            "mouth_slot": 6,
            "audio_channel": 2,
            "inputs": [] as [Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        let decoded = try JSONDecoder().decode(Creature.self, from: data)
        #expect(decoded.realData == false)
    }

    // MARK: Equality & hashing
    @Test("equality and hashing are consistent for identical values")
    func equalityAndHashing() throws {
        // Build once, then reconstruct via codable to get a distinct instance with identical values
        let original = Creature.mock()
        let data = try JSONEncoder().encode(original)
        let copy = try JSONDecoder().decode(Creature.self, from: data)
        #expect(original == copy)

        var set = Set<Creature>()
        set.insert(original)
        set.insert(copy)  // should collapse to one because they are equal
        #expect(set.count == 1)
    }

    @Test("changing any field breaks equality")
    func changingAFieldBreaksEquality() throws {
        let base = Creature.mock()
        let changedName = Creature(
            id: base.id,
            name: base.name + "!",
            channelOffset: base.channelOffset,
            mouthSlot: base.mouthSlot,
            audioChannel: base.audioChannel,
            inputs: base.inputs,
            realData: base.realData
        )
        #expect(base != changedName)

        let changedInputs = Creature(
            id: base.id,
            name: base.name,
            channelOffset: base.channelOffset,
            mouthSlot: base.mouthSlot,
            audioChannel: base.audioChannel,
            inputs: base.inputs + [Input(name: "Extra", slot: 9, width: 1, joystickAxis: 9)],
            realData: base.realData
        )
        #expect(base != changedInputs)

        let changedOffset = Creature(
            id: base.id,
            name: base.name,
            channelOffset: base.channelOffset + 1,
            mouthSlot: base.mouthSlot,
            audioChannel: base.audioChannel,
            inputs: base.inputs,
            realData: base.realData
        )
        #expect(base != changedOffset)

        let changedMouthSlot = Creature(
            id: base.id,
            name: base.name,
            channelOffset: base.channelOffset,
            mouthSlot: base.mouthSlot + 1,
            audioChannel: base.audioChannel,
            inputs: base.inputs,
            realData: base.realData
        )
        #expect(base != changedMouthSlot)

        let changedAudio = Creature(
            id: base.id,
            name: base.name,
            channelOffset: base.channelOffset,
            mouthSlot: base.mouthSlot,
            audioChannel: base.audioChannel + 1,
            inputs: base.inputs,
            realData: base.realData
        )
        #expect(base != changedAudio)

        let flippedFlag = Creature(
            id: base.id,
            name: base.name,
            channelOffset: base.channelOffset,
            mouthSlot: base.mouthSlot,
            audioChannel: base.audioChannel,
            inputs: base.inputs,
            realData: !base.realData
        )
        #expect(base != flippedFlag)
    }
}
