import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor PlaylistImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistImporter")

    // Upsert a batch of Playlist DTOs. This is safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Playlist]) async throws {
        guard !dtos.isEmpty else { return }

        // Fetch all existing playlists in one query for efficiency
        let allExistingDescriptor = FetchDescriptor<PlaylistModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                if let existing = existingByID[dto.id] {
                    // Update existing
                    existing.name = dto.name

                    // Update items: explicitly delete old ones before adding new ones
                    for item in existing.items {
                        modelContext.delete(item)
                    }
                    existing.items = dto.items.map { PlaylistItemModel(dto: $0) }
                } else {
                    // Insert new
                    modelContext.insert(PlaylistModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) playlists into SwiftData")
    }

    // Remove playlists not present in the provided set of ids (optional helper for full reloads)
    func deleteAllExcept(ids: Set<String>) async throws {
        let descriptor = FetchDescriptor<PlaylistModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted playlists not in provided id set; kept \(ids.count)")
    }
}
