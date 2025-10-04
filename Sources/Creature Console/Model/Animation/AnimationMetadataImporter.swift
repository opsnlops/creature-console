import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor AnimationMetadataImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationMetadataImporter")

    // Upsert a batch of AnimationMetadata DTOs. This is safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.AnimationMetadata]) async throws {
        guard !dtos.isEmpty else { return }

        // Fetch all existing animation metadata in one query for efficiency
        let allExistingDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                if let existing = existingByID[dto.id] {
                    // Update existing
                    existing.title = dto.title
                    existing.lastUpdated = dto.lastUpdated
                    existing.millisecondsPerFrame = dto.millisecondsPerFrame
                    existing.note = dto.note
                    existing.soundFile = dto.soundFile
                    existing.numberOfFrames = dto.numberOfFrames
                    existing.multitrackAudio = dto.multitrackAudio
                } else {
                    // Insert new
                    modelContext.insert(AnimationMetadataModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) animation metadata into SwiftData")
    }

    // Remove animation metadata not present in the provided set of ids (optional helper for full reloads)
    func deleteAllExcept(ids: Set<String>) async throws {
        let descriptor = FetchDescriptor<AnimationMetadataModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted animation metadata not in provided id set; kept \(ids.count)")
    }
}
