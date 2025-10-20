import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("SoundImporter operations")
struct SoundImporterTests {

    @Test("upsertBatch inserts new sounds")
    func upsertBatchInsertsNew() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        let dtos = [
            Common.Sound(
                fileName: "sound1.wav",
                size: 1024,
                transcript: "First sound",
                lipsync: "sound1.json"
            ),
            Common.Sound(
                fileName: "sound2.wav",
                size: 2048,
                transcript: "Second sound",
                lipsync: ""
            ),
        ]

        try await importer.upsertBatch(dtos)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(
            results.contains {
                $0.id == "sound1.wav" && $0.transcript == "First sound"
                    && $0.lipsync == "sound1.json"
            })
        #expect(
            results.contains {
                $0.id == "sound2.wav" && $0.transcript == "Second sound" && $0.lipsync.isEmpty
            })
    }

    @Test("upsertBatch updates existing sounds")
    func upsertBatchUpdatesExisting() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.Sound(
            fileName: "sound1.wav",
            size: 1024,
            transcript: "Original transcript",
            lipsync: "orig.json"
        )
        try await importer.upsertBatch([initialDTO])

        // Update with new data
        let updatedDTO = Common.Sound(
            fileName: "sound1.wav",
            size: 2048,
            transcript: "Updated transcript",
            lipsync: "updated.json"
        )
        try await importer.upsertBatch([updatedDTO])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "sound1.wav")
        #expect(results.first?.size == 2048)
        #expect(results.first?.transcript == "Updated transcript")
        #expect(results.first?.lipsync == "updated.json")
    }

    @Test("upsertBatch handles empty array")
    func upsertBatchHandlesEmpty() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        try await importer.upsertBatch([])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("deleteAllExcept removes sounds not in set")
    func deleteAllExceptRemovesOthers() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        let dtos = [
            Common.Sound(
                fileName: "keep1.wav",
                size: 1024,
                transcript: "Keep 1",
                lipsync: "keep1.json"
            ),
            Common.Sound(
                fileName: "keep2.wav",
                size: 2048,
                transcript: "Keep 2",
                lipsync: ""
            ),
            Common.Sound(
                fileName: "delete.wav",
                size: 4096,
                transcript: "Delete Me",
                lipsync: "delete.json"
            ),
        ]

        try await importer.upsertBatch(dtos)

        // Keep only keep1.wav and keep2.wav
        try await importer.deleteAllExcept(ids: ["keep1.wav", "keep2.wav"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "keep1.wav" })
        #expect(results.contains { $0.id == "keep2.wav" })
        #expect(!results.contains { $0.id == "delete.wav" })
    }

    @Test("deleteAllExcept handles empty database")
    func deleteAllExceptHandlesEmpty() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        // Should not throw on empty database
        try await importer.deleteAllExcept(ids: ["sound1.wav"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("upsertBatch with mix of new and existing")
    func upsertBatchMixedData() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.Sound(
            fileName: "existing.wav",
            size: 1024,
            transcript: "Existing",
            lipsync: "existing.json"
        )
        try await importer.upsertBatch([initialDTO])

        // Upsert with one existing and one new
        let mixedDTOs = [
            Common.Sound(
                fileName: "existing.wav",
                size: 2048,
                transcript: "Updated Existing",
                lipsync: "updated.json"
            ),
            Common.Sound(
                fileName: "new.wav",
                size: 4096,
                transcript: "Brand New",
                lipsync: "new.json"
            ),
        ]
        try await importer.upsertBatch(mixedDTOs)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        let existing = results.first { $0.id == "existing.wav" }
        #expect(existing?.size == 2048)
        #expect(existing?.transcript == "Updated Existing")
        #expect(existing?.lipsync == "updated.json")

        let new = results.first { $0.id == "new.wav" }
        #expect(new?.size == 4096)
        #expect(new?.transcript == "Brand New")
        #expect(new?.lipsync == "new.json")
    }

    @Test("upsertBatch handles empty transcript")
    func upsertBatchWithEmptyTranscript() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        let dto = Common.Sound(
            fileName: "silent.wav",
            size: 512,
            transcript: "",
            lipsync: ""
        )
        try await importer.upsertBatch([dto])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "silent.wav")
        #expect(results.first?.transcript == "")
    }

    @Test("upsertBatch preserves file extensions")
    func upsertBatchPreservesExtensions() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = SoundImporter(modelContainer: container)

        let dtos = [
            Common.Sound(
                fileName: "sound.wav", size: 1024, transcript: "WAV file", lipsync: "sound.json"),
            Common.Sound(fileName: "sound.mp3", size: 2048, transcript: "MP3 file", lipsync: ""),
            Common.Sound(
                fileName: "sound.m4a", size: 4096, transcript: "M4A file", lipsync: "m4a.json"),
        ]
        try await importer.upsertBatch(dtos)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 3)
        #expect(results.contains { $0.id == "sound.wav" })
        #expect(results.contains { $0.id == "sound.mp3" })
        #expect(results.contains { $0.id == "sound.m4a" })
    }
}
