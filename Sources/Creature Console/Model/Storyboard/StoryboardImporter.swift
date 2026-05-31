import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor StoryboardImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardImporter")

    /// Upsert a batch of Storyboard DTOs. Safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Storyboard]) async throws {
        guard !dtos.isEmpty else { return }

        let allExistingDescriptor = FetchDescriptor<StoryboardModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                let encodedTiles = (try? JSONEncoder().encode(dto.tiles)) ?? Data("[]".utf8)
                if let existing = existingByID[dto.id] {
                    existing.title = dto.title
                    existing.notes = dto.notes
                    existing.tilesJSON = encodedTiles
                    existing.createdAtMillis = dto.createdAt
                    existing.updatedAtMillis = dto.updatedAt
                } else {
                    modelContext.insert(StoryboardModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) storyboards into SwiftData")
    }

    /// Remove storyboards not present in the provided set of ids (used for full reloads).
    func deleteAllExcept(ids: Set<StoryboardIdentifier>) async throws {
        let descriptor = FetchDescriptor<StoryboardModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted storyboards not in provided id set; kept \(ids.count)")
    }
}
