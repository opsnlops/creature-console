import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("CreatureModel and InputModel basics")
struct CreatureModelTests {

    @Test("InputModel initializes with provided values")
    func inputInitializesWithValues() throws {
        let name = "Head Pan"
        let slot: UInt16 = 1
        let width: UInt8 = 8
        let joystickAxis: UInt8 = 2

        let input = InputModel(name: name, slot: slot, width: width, joystickAxis: joystickAxis)

        #expect(input.name == name)
        #expect(input.slot == slot)
        #expect(input.width == width)
        #expect(input.joystickAxis == joystickAxis)
        #expect(input.creature == nil)
    }

    @Test("InputModel converts from DTO")
    func inputConvertsFromDTO() throws {
        let dto = Common.Input(name: "Eye Tilt", slot: 2, width: 16, joystickAxis: 3)
        let input = InputModel(dto: dto)

        #expect(input.name == dto.name)
        #expect(input.slot == dto.slot)
        #expect(input.width == dto.width)
        #expect(input.joystickAxis == dto.joystickAxis)
    }

    @Test("InputModel converts to DTO")
    func inputConvertsToDTO() throws {
        let input = InputModel(name: "Jaw", slot: 3, width: 8, joystickAxis: 4)
        let dto = input.toDTO()

        #expect(dto.name == input.name)
        #expect(dto.slot == input.slot)
        #expect(dto.width == input.width)
        #expect(dto.joystickAxis == input.joystickAxis)
    }

    @Test("CreatureModel initializes with provided values")
    func creatureInitializesWithValues() throws {
        let id = "creature_123"
        let name = "Test Creature"
        let channelOffset = 10
        let mouthSlot = 4
        let realData = true
        let audioChannel = 1
        let inputs = [
            InputModel(name: "Input1", slot: 1, width: 8, joystickAxis: 0),
            InputModel(name: "Input2", slot: 2, width: 16, joystickAxis: 1),
        ]

        let creature = CreatureModel(
            id: id,
            name: name,
            channelOffset: channelOffset,
            mouthSlot: mouthSlot,
            realData: realData,
            audioChannel: audioChannel,
            inputs: inputs
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
            realData: false
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
    }

    @Test("CreatureModel converts to DTO")
    func creatureConvertsToDTO() throws {
        let inputs = [
            InputModel(name: "Input X", slot: 5, width: 8, joystickAxis: 2),
            InputModel(name: "Input Y", slot: 6, width: 16, joystickAxis: 3),
        ]
        let creature = CreatureModel(
            id: "creature_789",
            name: "Model Creature",
            channelOffset: 30,
            mouthSlot: 6,
            realData: true,
            audioChannel: 3,
            inputs: inputs
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
            realData: true
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
    }

    @Test("CreatureModel persists with cascade delete relationship")
    func creaturePersistsWithCascadeDelete() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let inputs = [
            InputModel(name: "Cascade Input 1", slot: 1, width: 8, joystickAxis: 0),
            InputModel(name: "Cascade Input 2", slot: 2, width: 16, joystickAxis: 1),
        ]
        let creature = CreatureModel(
            id: "creature_cascade",
            name: "Cascade Test",
            channelOffset: 0,
            mouthSlot: 1,
            realData: false,
            audioChannel: 0,
            inputs: inputs
        )

        context.insert(creature)
        try context.save()

        let creatureFetch = FetchDescriptor<CreatureModel>()
        var creatureResults = try context.fetch(creatureFetch)
        #expect(creatureResults.count == 1)

        let inputFetch = FetchDescriptor<InputModel>()
        var inputResults = try context.fetch(inputFetch)
        #expect(inputResults.count == 2)

        // Delete the creature
        context.delete(creature)
        try context.save()

        creatureResults = try context.fetch(creatureFetch)
        #expect(creatureResults.count == 0)

        // Inputs should be cascade deleted
        inputResults = try context.fetch(inputFetch)
        #expect(inputResults.count == 0)
    }

    @Test("CreatureModel enforces unique ID constraint")
    func creatureEnforcesUniqueID() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let creature1 = CreatureModel(
            id: "creature_unique",
            name: "First",
            channelOffset: 0,
            mouthSlot: 1,
            realData: false,
            audioChannel: 0,
            inputs: []
        )
        let creature2 = CreatureModel(
            id: "creature_unique",
            name: "Second",
            channelOffset: 10,
            mouthSlot: 3,
            realData: true,
            audioChannel: 1,
            inputs: []
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

    @Test("InputModel maintains inverse relationship to creature")
    func inputMaintainsInverseRelationship() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let inputs = [
            InputModel(name: "Rel Input 1", slot: 1, width: 8, joystickAxis: 0),
            InputModel(name: "Rel Input 2", slot: 2, width: 16, joystickAxis: 1),
        ]
        let creature = CreatureModel(
            id: "creature_rel",
            name: "Relationship Test",
            channelOffset: 0,
            mouthSlot: 2,
            realData: false,
            audioChannel: 0,
            inputs: inputs
        )

        context.insert(creature)
        try context.save()

        // Check inverse relationship
        #expect(inputs[0].creature?.id == "creature_rel")
        #expect(inputs[1].creature?.id == "creature_rel")
    }
}
