import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("AnimationMetadataImporter operations")
struct AnimationMetadataImporterTests {

    @Test("upsertBatch inserts new animation metadata")
    func upsertBatchInsertsNew() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        let dtos = [
            Common.AnimationMetadata(
                id: "anim_1",
                title: "Animation 1",
                lastUpdated: Date(),
                millisecondsPerFrame: 20,
                note: "Test note",
                soundFile: "test.wav",
                numberOfFrames: 100,
                multitrackAudio: false
            ),
            Common.AnimationMetadata(
                id: "anim_2",
                title: "Animation 2",
                lastUpdated: Date(),
                millisecondsPerFrame: 30,
                note: "",
                soundFile: "",
                numberOfFrames: 50,
                multitrackAudio: true
            ),
        ]

        try await importer.upsertBatch(dtos)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "anim_1" && $0.title == "Animation 1" })
        #expect(results.contains { $0.id == "anim_2" && $0.title == "Animation 2" })
    }

    @Test("upsertBatch updates existing animation metadata")
    func upsertBatchUpdatesExisting() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.AnimationMetadata(
            id: "anim_1",
            title: "Original Title",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "Original note",
            soundFile: "original.wav",
            numberOfFrames: 100,
            multitrackAudio: false
        )
        try await importer.upsertBatch([initialDTO])

        // Update with new data
        let updatedDTO = Common.AnimationMetadata(
            id: "anim_1",
            title: "Updated Title",
            lastUpdated: Date(),
            millisecondsPerFrame: 30,
            note: "Updated note",
            soundFile: "updated.wav",
            numberOfFrames: 200,
            multitrackAudio: true
        )
        try await importer.upsertBatch([updatedDTO])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "anim_1")
        #expect(results.first?.title == "Updated Title")
        #expect(results.first?.millisecondsPerFrame == 30)
        #expect(results.first?.note == "Updated note")
        #expect(results.first?.soundFile == "updated.wav")
        #expect(results.first?.numberOfFrames == 200)
        #expect(results.first?.multitrackAudio == true)
    }

    @Test("upsertBatch handles empty array")
    func upsertBatchHandlesEmpty() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        try await importer.upsertBatch([])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("deleteAllExcept removes animations not in set")
    func deleteAllExceptRemovesOthers() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        let dtos = [
            Common.AnimationMetadata(
                id: "anim_1",
                title: "Keep 1",
                lastUpdated: Date(),
                millisecondsPerFrame: 20,
                note: "",
                soundFile: "",
                numberOfFrames: 100,
                multitrackAudio: false
            ),
            Common.AnimationMetadata(
                id: "anim_2",
                title: "Keep 2",
                lastUpdated: Date(),
                millisecondsPerFrame: 20,
                note: "",
                soundFile: "",
                numberOfFrames: 100,
                multitrackAudio: false
            ),
            Common.AnimationMetadata(
                id: "anim_3",
                title: "Delete Me",
                lastUpdated: Date(),
                millisecondsPerFrame: 20,
                note: "",
                soundFile: "",
                numberOfFrames: 100,
                multitrackAudio: false
            ),
        ]

        try await importer.upsertBatch(dtos)

        // Keep only anim_1 and anim_2
        try await importer.deleteAllExcept(ids: ["anim_1", "anim_2"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "anim_1" })
        #expect(results.contains { $0.id == "anim_2" })
        #expect(!results.contains { $0.id == "anim_3" })
    }

    @Test("deleteAllExcept handles empty database")
    func deleteAllExceptHandlesEmpty() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        // Should not throw on empty database
        try await importer.deleteAllExcept(ids: ["anim_1"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("upsertBatch with mix of new and existing")
    func upsertBatchMixedData() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = AnimationMetadataImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.AnimationMetadata(
            id: "anim_1",
            title: "Existing",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "",
            soundFile: "",
            numberOfFrames: 100,
            multitrackAudio: false
        )
        try await importer.upsertBatch([initialDTO])

        // Upsert with one existing and one new
        let mixedDTOs = [
            Common.AnimationMetadata(
                id: "anim_1",
                title: "Updated Existing",
                lastUpdated: Date(),
                millisecondsPerFrame: 30,
                note: "",
                soundFile: "",
                numberOfFrames: 150,
                multitrackAudio: false
            ),
            Common.AnimationMetadata(
                id: "anim_2",
                title: "Brand New",
                lastUpdated: Date(),
                millisecondsPerFrame: 40,
                note: "",
                soundFile: "",
                numberOfFrames: 200,
                multitrackAudio: true
            ),
        ]
        try await importer.upsertBatch(mixedDTOs)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        let anim1 = results.first { $0.id == "anim_1" }
        #expect(anim1?.title == "Updated Existing")
        #expect(anim1?.millisecondsPerFrame == 30)

        let anim2 = results.first { $0.id == "anim_2" }
        #expect(anim2?.title == "Brand New")
        #expect(anim2?.multitrackAudio == true)
    }
}
