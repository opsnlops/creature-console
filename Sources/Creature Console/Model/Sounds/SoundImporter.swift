import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor SoundImporter {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundImporter")

    // Upsert a batch of Sound DTOs. This is safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Sound]) async throws {
        guard !dtos.isEmpty else { return }

        // Fetch all existing sounds in one query for efficiency
        let allExistingDescriptor = FetchDescriptor<SoundModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                if let existing = existingByID[dto.fileName] {
                    // Update existing
                    existing.size = dto.size
                    existing.transcript = dto.transcript
                    existing.lipsync = dto.lipsync
                } else {
                    // Insert new
                    modelContext.insert(SoundModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) sounds into SwiftData")
    }

    // Remove sounds not present in the provided set of ids (optional helper for full reloads)
    func deleteAllExcept(ids: Set<String>) async throws {
        let descriptor = FetchDescriptor<SoundModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted sounds not in provided id set; kept \(ids.count)")
    }
}
