import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("PlaylistModel and PlaylistItemModel basics")
struct PlaylistModelTests {

    @Test("PlaylistItemModel initializes with provided values")
    func playlistItemInitializesWithValues() throws {
        let animationId = "anim_123"
        let weight: UInt32 = 5

        let item = PlaylistItemModel(animationId: animationId, weight: weight)

        #expect(item.animationId == animationId)
        #expect(item.weight == weight)
        #expect(item.playlist == nil)
    }

    @Test("PlaylistItemModel converts from DTO")
    func playlistItemConvertsFromDTO() throws {
        let dto = Common.PlaylistItem(animationId: "anim_456", weight: 3)
        let item = PlaylistItemModel(dto: dto)

        #expect(item.animationId == dto.animationId)
        #expect(item.weight == dto.weight)
    }

    @Test("PlaylistItemModel converts to DTO")
    func playlistItemConvertsToDTO() throws {
        let item = PlaylistItemModel(animationId: "anim_789", weight: 7)
        let dto = item.toDTO()

        #expect(dto.animationId == item.animationId)
        #expect(dto.weight == item.weight)
    }

    @Test("PlaylistModel initializes with provided values")
    func playlistInitializesWithValues() throws {
        let id: PlaylistIdentifier = "playlist_123"
        let name = "Test Playlist"
        let items = [
            PlaylistItemModel(animationId: "anim_1", weight: 1),
            PlaylistItemModel(animationId: "anim_2", weight: 2),
        ]

        let playlist = PlaylistModel(id: id, name: name, items: items)

        #expect(playlist.id == id)
        #expect(playlist.name == name)
        #expect(playlist.items.count == 2)
        #expect(playlist.items[0].animationId == "anim_1")
        #expect(playlist.items[1].animationId == "anim_2")
    }

    @Test("PlaylistModel converts from DTO")
    func playlistConvertsFromDTO() throws {
        let dto = Common.Playlist(
            id: "playlist_456",
            name: "DTO Playlist",
            items: [
                Common.PlaylistItem(animationId: "anim_a", weight: 10),
                Common.PlaylistItem(animationId: "anim_b", weight: 20),
            ]
        )

        let playlist = PlaylistModel(dto: dto)

        #expect(playlist.id == dto.id)
        #expect(playlist.name == dto.name)
        #expect(playlist.items.count == 2)
        #expect(playlist.items[0].animationId == "anim_a")
        #expect(playlist.items[0].weight == 10)
        #expect(playlist.items[1].animationId == "anim_b")
        #expect(playlist.items[1].weight == 20)
    }

    @Test("PlaylistModel converts to DTO")
    func playlistConvertsToDTO() throws {
        let items = [
            PlaylistItemModel(animationId: "anim_x", weight: 5),
            PlaylistItemModel(animationId: "anim_y", weight: 15),
        ]
        let playlist = PlaylistModel(id: "playlist_789", name: "Model Playlist", items: items)

        let dto = playlist.toDTO()

        #expect(dto.id == playlist.id)
        #expect(dto.name == playlist.name)
        #expect(dto.items.count == 2)
        #expect(dto.items[0].animationId == "anim_x")
        #expect(dto.items[0].weight == 5)
        #expect(dto.items[1].animationId == "anim_y")
        #expect(dto.items[1].weight == 15)
    }

    @Test("PlaylistModel round-trips through DTO conversion")
    func playlistRoundTripsDTO() throws {
        let originalDTO = Common.Playlist(
            id: "playlist_round",
            name: "Round Trip Playlist",
            items: [
                Common.PlaylistItem(animationId: "anim_1", weight: 1),
                Common.PlaylistItem(animationId: "anim_2", weight: 2),
                Common.PlaylistItem(animationId: "anim_3", weight: 3),
            ]
        )

        let playlist = PlaylistModel(dto: originalDTO)
        let convertedDTO = playlist.toDTO()

        #expect(convertedDTO.id == originalDTO.id)
        #expect(convertedDTO.name == originalDTO.name)
        #expect(convertedDTO.items.count == originalDTO.items.count)
        for (index, item) in convertedDTO.items.enumerated() {
            #expect(item.animationId == originalDTO.items[index].animationId)
            #expect(item.weight == originalDTO.items[index].weight)
        }
    }

    @Test("PlaylistModel persists with cascade delete relationship")
    func playlistPersistsWithCascadeDelete() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            PlaylistItemModel(animationId: "anim_cascade_1", weight: 1),
            PlaylistItemModel(animationId: "anim_cascade_2", weight: 2),
        ]
        let playlist = PlaylistModel(id: "playlist_cascade", name: "Cascade Test", items: items)

        context.insert(playlist)
        try context.save()

        let playlistFetch = FetchDescriptor<PlaylistModel>()
        var playlistResults = try context.fetch(playlistFetch)
        #expect(playlistResults.count == 1)

        let itemFetch = FetchDescriptor<PlaylistItemModel>()
        var itemResults = try context.fetch(itemFetch)
        #expect(itemResults.count == 2)

        // Delete the playlist
        context.delete(playlist)
        try context.save()

        playlistResults = try context.fetch(playlistFetch)
        #expect(playlistResults.count == 0)

        // Items should be cascade deleted
        itemResults = try context.fetch(itemFetch)
        #expect(itemResults.count == 0)
    }

    @Test("PlaylistModel enforces unique ID constraint")
    func playlistEnforcesUniqueID() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let playlist1 = PlaylistModel(id: "playlist_unique", name: "First", items: [])
        let playlist2 = PlaylistModel(id: "playlist_unique", name: "Second", items: [])

        context.insert(playlist1)
        try context.save()

        context.insert(playlist2)
        try context.save()

        let fetchDescriptor = FetchDescriptor<PlaylistModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.name == "Second")
    }

    @Test("PlaylistItemModel maintains inverse relationship to playlist")
    func playlistItemMaintainsInverseRelationship() async throws {
        let schema = Schema([PlaylistModel.self, PlaylistItemModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            PlaylistItemModel(animationId: "anim_rel_1", weight: 1),
            PlaylistItemModel(animationId: "anim_rel_2", weight: 2),
        ]
        let playlist = PlaylistModel(id: "playlist_rel", name: "Relationship Test", items: items)

        context.insert(playlist)
        try context.save()

        // Check inverse relationship
        #expect(items[0].playlist?.id == "playlist_rel")
        #expect(items[1].playlist?.id == "playlist_rel")
    }
}
