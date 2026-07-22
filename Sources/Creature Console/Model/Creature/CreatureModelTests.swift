import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("CreatureModel basics")
struct CreatureModelTests {

    @Test("CreatureModel initializes with provided values")
    func creatureInitializesWithValues() throws {
        let id = "creature_123"
        let name = "Test Creature"
        let channelOffset = 10
        let mouthSlot = 4
        let realData = true
        let audioChannel = 1
        let speechLoopIds = ["speech1", "speech2"]
        let idleIds = ["idle1", "idle2"]
        let inputs = [
            Common.Input(name: "Input1", slot: 1, width: 8, joystickAxis: 0),
            Common.Input(name: "Input2", slot: 2, width: 16, joystickAxis: 1),
        ]

        let creature = CreatureModel(
            id: id,
            name: name,
            channelOffset: channelOffset,
            mouthSlot: mouthSlot,
            realData: realData,
            audioChannel: audioChannel,
            inputs: inputs,
            speechLoopAnimationIds: speechLoopIds,
            idleAnimationIds: idleIds
        )

        #expect(creature.id == id)
        #expect(creature.name == name)
        #expect(creature.channelOffset == channelOffset)
        #expect(creature.mouthSlot == mouthSlot)
        #expect(creature.realData == realData)
        #expect(creature.audioChannel == audioChannel)
        #expect(creature.inputs.count == 2)
        #expect(creature.inputs[0].name == "Input1")
        #expect(creature.inputs[1].name == "Input2")
        #expect(creature.speechLoopAnimationIds == speechLoopIds)
        #expect(creature.idleAnimationIds == idleIds)
    }

    @Test("CreatureModel converts from DTO")
    func creatureConvertsFromDTO() throws {
        let dto = Common.Creature(
            id: "creature_456",
            name: "DTO Creature",
            channelOffset: 20,
            mouthSlot: 5,
            audioChannel: 2,
            inputs: [
                Common.Input(name: "Input A", slot: 1, width: 8, joystickAxis: 0),
                Common.Input(name: "Input B", slot: 2, width: 16, joystickAxis: 1),
            ],
            realData: false,
            speechLoopAnimationIds: ["speech-loop-1"],
            idleAnimationIds: ["idle-loop-1", "idle-loop-2"]
        )

        let creature = CreatureModel(dto: dto)

        #expect(creature.id == dto.id)
        #expect(creature.name == dto.name)
        #expect(creature.channelOffset == dto.channelOffset)
        #expect(creature.mouthSlot == dto.mouthSlot)
        #expect(creature.realData == dto.realData)
        #expect(creature.audioChannel == dto.audioChannel)
        #expect(creature.inputs.count == 2)
        #expect(creature.inputs[0].name == "Input A")
        #expect(creature.inputs[0].slot == 1)
        #expect(creature.inputs[1].name == "Input B")
        #expect(creature.inputs[1].slot == 2)
        #expect(creature.speechLoopAnimationIds == dto.speechLoopAnimationIds)
        #expect(creature.idleAnimationIds == dto.idleAnimationIds)
    }

    @Test("CreatureModel converts to DTO")
    func creatureConvertsToDTO() throws {
        let inputs = [
            Common.Input(name: "Input X", slot: 5, width: 8, joystickAxis: 2),
            Common.Input(name: "Input Y", slot: 6, width: 16, joystickAxis: 3),
        ]
        let creature = CreatureModel(
            id: "creature_789",
            name: "Model Creature",
            channelOffset: 30,
            mouthSlot: 6,
            realData: true,
            audioChannel: 3,
            inputs: inputs,
            speechLoopAnimationIds: ["speech-loop-A"],
            idleAnimationIds: ["idle-loop-A"]
        )

        let dto = creature.toDTO()

        #expect(dto.id == creature.id)
        #expect(dto.name == creature.name)
        #expect(dto.channelOffset == creature.channelOffset)
        #expect(dto.mouthSlot == creature.mouthSlot)
        #expect(dto.realData == creature.realData)
        #expect(dto.audioChannel == creature.audioChannel)
        #expect(dto.inputs.count == 2)
        #expect(dto.inputs[0].name == "Input X")
        #expect(dto.inputs[0].slot == 5)
        #expect(dto.inputs[1].name == "Input Y")
        #expect(dto.inputs[1].slot == 6)
        #expect(dto.speechLoopAnimationIds == creature.speechLoopAnimationIds)
        #expect(dto.idleAnimationIds == creature.idleAnimationIds)
    }

    @Test("CreatureModel round-trips through DTO conversion")
    func creatureRoundTripsDTO() throws {
        let originalDTO = Common.Creature(
            id: "creature_round",
            name: "Round Trip Creature",
            channelOffset: 40,
            mouthSlot: 2,
            audioChannel: 4,
            inputs: [
                Common.Input(name: "Input 1", slot: 1, width: 8, joystickAxis: 0),
                Common.Input(name: "Input 2", slot: 2, width: 16, joystickAxis: 1),
                Common.Input(name: "Input 3", slot: 3, width: 8, joystickAxis: 2),
            ],
            realData: true,
            speechLoopAnimationIds: ["speech-loop-round"],
            idleAnimationIds: ["idle-loop-round"]
        )

        let creature = CreatureModel(dto: originalDTO)
        let convertedDTO = creature.toDTO()

        #expect(convertedDTO.id == originalDTO.id)
        #expect(convertedDTO.name == originalDTO.name)
        #expect(convertedDTO.channelOffset == originalDTO.channelOffset)
        #expect(convertedDTO.mouthSlot == originalDTO.mouthSlot)
        #expect(convertedDTO.realData == originalDTO.realData)
        #expect(convertedDTO.audioChannel == originalDTO.audioChannel)
        #expect(convertedDTO.inputs.count == originalDTO.inputs.count)
        for (index, input) in convertedDTO.inputs.enumerated() {
            #expect(input.name == originalDTO.inputs[index].name)
            #expect(input.slot == originalDTO.inputs[index].slot)
            #expect(input.width == originalDTO.inputs[index].width)
            #expect(input.joystickAxis == originalDTO.inputs[index].joystickAxis)
        }
        #expect(convertedDTO.speechLoopAnimationIds == originalDTO.speechLoopAnimationIds)
        #expect(convertedDTO.idleAnimationIds == originalDTO.idleAnimationIds)
    }

    @Test("CreatureModel persists and decodes its inputs blob")
    func creaturePersistsInputs() async throws {
        let schema = Schema([CreatureModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)
        let context = ModelContext(container)

        let creature = CreatureModel(
            id: "creature_persist",
            name: "Persist Test",
            channelOffset: 0,
            mouthSlot: 1,
            realData: false,
            audioChannel: 0,
            inputs: [
                Common.Input(name: "Blob Input 1", slot: 1, width: 8, joystickAxis: 0),
                Common.Input(name: "Blob Input 2", slot: 2, width: 16, joystickAxis: 1),
            ],
            speechLoopAnimationIds: [],
            idleAnimationIds: []
        )

        context.insert(creature)
        try context.save()

        let results = try context.fetch(FetchDescriptor<CreatureModel>())
        #expect(results.count == 1)
        #expect(results.first?.inputs.count == 2)
        #expect(results.first?.inputs.first?.name == "Blob Input 1")

        // No child models to orphan — deleting the creature leaves nothing behind.
        context.delete(creature)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<CreatureModel>()).isEmpty)
    }

    @Test("CreatureModel enforces unique ID constraint")
    func creatureEnforcesUniqueID() async throws {
        let schema = Schema([CreatureModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)
        let context = ModelContext(container)

        let creature1 = CreatureModel(
            id: "creature_unique",
            name: "First",
            channelOffset: 0,
            mouthSlot: 1,
            realData: false,
            audioChannel: 0,
            inputs: [],
            speechLoopAnimationIds: [],
            idleAnimationIds: []
        )
        let creature2 = CreatureModel(
            id: "creature_unique",
            name: "Second",
            channelOffset: 10,
            mouthSlot: 3,
            realData: true,
            audioChannel: 1,
            inputs: [],
            speechLoopAnimationIds: [],
            idleAnimationIds: []
        )

        context.insert(creature1)
        try context.save()

        context.insert(creature2)
        try context.save()

        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.name == "Second")
    }
}
