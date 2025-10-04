import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("PlaylistImporter operations")
struct PlaylistImporterTests {

    @Test("upsertBatch inserts new playlists")
    func upsertBatchInsertsNew() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        let dtos = [
            Common.Playlist(
                id: "playlist_1",
                name: "Playlist 1",
                items: [
                    Common.PlaylistItem(animationId: "anim_1", weight: 1),
                    Common.PlaylistItem(animationId: "anim_2", weight: 2),
                ]
            ),
            Common.Playlist(
                id: "playlist_2",
                name: "Playlist 2",
                items: [
                    Common.PlaylistItem(animationId: "anim_3", weight: 3)
                ]
            ),
        ]

        try await importer.upsertBatch(dtos)

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        let playlist1 = results.first { $0.id == "playlist_1" }
        #expect(playlist1?.name == "Playlist 1")
        #expect(playlist1?.items.count == 2)

        let playlist2 = results.first { $0.id == "playlist_2" }
        #expect(playlist2?.name == "Playlist 2")
        #expect(playlist2?.items.count == 1)
    }

    @Test("upsertBatch updates existing playlists and items")
    func upsertBatchUpdatesExisting() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        // Insert initial data
        let initialDTO = Common.Playlist(
            id: "playlist_1",
            name: "Original Name",
            items: [
                Common.PlaylistItem(animationId: "anim_1", weight: 1),
                Common.PlaylistItem(animationId: "anim_2", weight: 2),
            ]
        )
        try await importer.upsertBatch([initialDTO])

        // Update with new data - different name and different items
        let updatedDTO = Common.Playlist(
            id: "playlist_1",
            name: "Updated Name",
            items: [
                Common.PlaylistItem(animationId: "anim_3", weight: 5),
                Common.PlaylistItem(animationId: "anim_4", weight: 10),
                Common.PlaylistItem(animationId: "anim_5", weight: 15),
            ]
        )
        try await importer.upsertBatch([updatedDTO])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "playlist_1")
        #expect(results.first?.name == "Updated Name")
        #expect(results.first?.items.count == 3)
        #expect(
            results.first?.items.contains { $0.animationId == "anim_3" && $0.weight == 5 } == true)
        #expect(
            results.first?.items.contains { $0.animationId == "anim_4" && $0.weight == 10 } == true)
        #expect(
            results.first?.items.contains { $0.animationId == "anim_5" && $0.weight == 15 } == true)
    }

    @Test("upsertBatch deletes old items when updating")
    func upsertBatchDeletesOldItems() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        // Insert initial data with 3 items
        let initialDTO = Common.Playlist(
            id: "playlist_1",
            name: "Test Playlist",
            items: [
                Common.PlaylistItem(animationId: "anim_1", weight: 1),
                Common.PlaylistItem(animationId: "anim_2", weight: 2),
                Common.PlaylistItem(animationId: "anim_3", weight: 3),
            ]
        )
        try await importer.upsertBatch([initialDTO])

        // Update with only 1 item
        let updatedDTO = Common.Playlist(
            id: "playlist_1",
            name: "Test Playlist",
            items: [
                Common.PlaylistItem(animationId: "anim_4", weight: 4)
            ]
        )
        try await importer.upsertBatch([updatedDTO])

        let context = ModelContext(container)

        // Check playlist has new items
        let playlistFetch = FetchDescriptor<PlaylistModel>()
        let playlists = try context.fetch(playlistFetch)
        #expect(playlists.count == 1)
        #expect(playlists.first?.items.count == 1)
        #expect(playlists.first?.items.first?.animationId == "anim_4")
        #expect(playlists.first?.items.first?.weight == 4)

        // Verify old items were deleted (not orphaned)
        let itemFetch = FetchDescriptor<PlaylistItemModel>()
        let items = try context.fetch(itemFetch)
        #expect(items.count == 1)
        #expect(items.first?.animationId == "anim_4")
    }

    @Test("upsertBatch handles empty array")
    func upsertBatchHandlesEmpty() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        try await importer.upsertBatch([])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("deleteAllExcept removes playlists not in set")
    func deleteAllExceptRemovesOthers() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        let dtos = [
            Common.Playlist(id: "playlist_1", name: "Keep 1", items: []),
            Common.Playlist(id: "playlist_2", name: "Keep 2", items: []),
            Common.Playlist(id: "playlist_3", name: "Delete Me", items: []),
        ]

        try await importer.upsertBatch(dtos)

        // Keep only playlist_1 and playlist_2
        try await importer.deleteAllExcept(ids: ["playlist_1", "playlist_2"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "playlist_1" })
        #expect(results.contains { $0.id == "playlist_2" })
        #expect(!results.contains { $0.id == "playlist_3" })
    }

    @Test("deleteAllExcept handles empty database")
    func deleteAllExceptHandlesEmpty() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        // Should not throw on empty database
        try await importer.deleteAllExcept(ids: ["playlist_1"])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("upsertBatch with empty items array")
    func upsertBatchWithEmptyItems() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let importer = PlaylistImporter(modelContainer: container)

        let dto = Common.Playlist(id: "playlist_1", name: "Empty Playlist", items: [])
        try await importer.upsertBatch([dto])

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.items.isEmpty == true)
    }
}
