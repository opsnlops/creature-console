import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("CreatureImporter operations")
struct CreatureImporterTests {

    @Test("upsertBatch inserts new creatures")
    func upsertBatchInsertsNew() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        let dtos = [
            Common.Creature(
                id: "creature_1",
                name: "Creature 1",
                channelOffset: 10,
                mouthSlot: 2,
                audioChannel: 1,
                inputs: [
                    Common.Input(name: "Input 1", slot: 1, width: 8, joystickAxis: 0),
                    Common.Input(name: "Input 2", slot: 2, width: 16, joystickAxis: 1),
                ],
                realData: true
            ),
            Common.Creature(
                id: "creature_2",
                name: "Creature 2",
                channelOffset: 20,
                mouthSlot: 3,
                audioChannel: 2,
                inputs: [
                    Common.Input(name: "Input 3", slot: 3, width: 8, joystickAxis: 2)
                ],
                realData: false
            ),
        ]

        try await importer.upsertBatch(dtos)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        let creature1 = results.first { $0.id == "creature_1" }
        #expect(creature1?.name == "Creature 1")
        #expect(creature1?.mouthSlot == 2)
        #expect(creature1?.inputs.count == 2)
        #expect(creature1?.realData == true)

        let creature2 = results.first { $0.id == "creature_2" }
        #expect(creature2?.name == "Creature 2")
        #expect(creature2?.mouthSlot == 3)
        #expect(creature2?.inputs.count == 1)
        #expect(creature2?.realData == false)
    }

    @Test("upsertBatch updates existing creatures and inputs")
    func upsertBatchUpdatesExisting() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.Creature(
            id: "creature_1",
            name: "Original Name",
            channelOffset: 10,
            mouthSlot: 4,
            audioChannel: 1,
            inputs: [
                Common.Input(name: "Input 1", slot: 1, width: 8, joystickAxis: 0),
                Common.Input(name: "Input 2", slot: 2, width: 16, joystickAxis: 1),
            ],
            realData: true
        )
        try await importer.upsertBatch([initialDTO])

        // Update with new data
        let updatedDTO = Common.Creature(
            id: "creature_1",
            name: "Updated Name",
            channelOffset: 20,
            mouthSlot: 5,
            audioChannel: 2,
            inputs: [
                Common.Input(name: "Input 3", slot: 3, width: 8, joystickAxis: 2),
                Common.Input(name: "Input 4", slot: 4, width: 16, joystickAxis: 3),
                Common.Input(name: "Input 5", slot: 5, width: 8, joystickAxis: 4),
            ],
            realData: false
        )
        try await importer.upsertBatch([updatedDTO])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "creature_1")
        #expect(results.first?.name == "Updated Name")
        #expect(results.first?.channelOffset == 20)
        #expect(results.first?.mouthSlot == 5)
        #expect(results.first?.audioChannel == 2)
        #expect(results.first?.realData == false)
        #expect(results.first?.inputs.count == 3)
        #expect(results.first?.inputs.contains { $0.name == "Input 3" } == true)
    }

    @Test("upsertBatch deletes old inputs when updating")
    func upsertBatchDeletesOldInputs() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        // Insert initial data with 3 inputs
        let initialDTO = Common.Creature(
            id: "creature_1",
            name: "Test Creature",
            channelOffset: 10,
            mouthSlot: 6,
            audioChannel: 1,
            inputs: [
                Common.Input(name: "Input 1", slot: 1, width: 8, joystickAxis: 0),
                Common.Input(name: "Input 2", slot: 2, width: 16, joystickAxis: 1),
                Common.Input(name: "Input 3", slot: 3, width: 8, joystickAxis: 2),
            ],
            realData: true
        )
        try await importer.upsertBatch([initialDTO])

        // Update with only 1 input
        let updatedDTO = Common.Creature(
            id: "creature_1",
            name: "Test Creature",
            channelOffset: 10,
            mouthSlot: 6,
            audioChannel: 1,
            inputs: [
                Common.Input(name: "Input 4", slot: 4, width: 16, joystickAxis: 3)
            ],
            realData: true
        )
        try await importer.upsertBatch([updatedDTO])

        // Query from a fresh context to verify persistence
        let context = ModelContext(container)
        let creatureFetch = FetchDescriptor<CreatureModel>(
            predicate: #Predicate { $0.id == "creature_1" }
        )
        let creatures = try context.fetch(creatureFetch)

        #expect(creatures.count == 1)

        guard let creature = creatures.first else {
            Issue.record("Expected to find creature_1")
            return
        }

        #expect(creature.inputs.count == 1)
        #expect(creature.inputs.first?.name == "Input 4")
        #expect(creature.inputs.first?.slot == 4)

        // Verify old inputs were deleted (not orphaned)
        let inputFetch = FetchDescriptor<InputModel>()
        let inputs = try context.fetch(inputFetch)
        #expect(inputs.count == 1)
        #expect(inputs.first?.name == "Input 4")
    }

    @Test("upsertBatch handles empty array")
    func upsertBatchHandlesEmpty() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        try await importer.upsertBatch([])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("deleteAllExcept removes creatures not in set")
    func deleteAllExceptRemovesOthers() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        let dtos = [
            Common.Creature(
                id: "creature_1", name: "Keep 1", channelOffset: 10, mouthSlot: 2, audioChannel: 1,
                inputs: [],
                realData: true),
            Common.Creature(
                id: "creature_2", name: "Keep 2", channelOffset: 20, mouthSlot: 4, audioChannel: 2,
                inputs: [],
                realData: false),
            Common.Creature(
                id: "creature_3", name: "Delete Me", channelOffset: 30, mouthSlot: 6,
                audioChannel: 3, inputs: [],
                realData: true),
        ]

        try await importer.upsertBatch(dtos)

        // Keep only creature_1 and creature_2
        try await importer.deleteAllExcept(ids: ["creature_1", "creature_2"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "creature_1" })
        #expect(results.contains { $0.id == "creature_2" })
        #expect(!results.contains { $0.id == "creature_3" })
    }

    @Test("deleteAllExcept handles empty database")
    func deleteAllExceptHandlesEmpty() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        // Should not throw on empty database
        try await importer.deleteAllExcept(ids: ["creature_1"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("upsertBatch with empty inputs array")
    func upsertBatchWithEmptyInputs() async throws {
        let schema = Schema([CreatureModel.self, InputModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = CreatureImporter(modelContainer: container)

        let dto = Common.Creature(
            id: "creature_1",
            name: "No Inputs Creature",
            channelOffset: 10,
            mouthSlot: 3,
            audioChannel: 1,
            inputs: [],
            realData: true
        )
        try await importer.upsertBatch([dto])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<CreatureModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.inputs.isEmpty == true)
    }
}
