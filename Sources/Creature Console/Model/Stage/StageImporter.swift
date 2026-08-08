import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor StageImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StageImporter")

    /// Upsert a batch of Stage DTOs. Safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Stage]) async throws {
        guard !dtos.isEmpty else { return }

        let allExisting = try modelContext.fetch(FetchDescriptor<StageModel>())
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                let placements = (try? JSONEncoder().encode(dto.placements)) ?? Data("[]".utf8)
                let audio = (try? JSONEncoder().encode(dto.audio)) ?? Data("{}".utf8)
                if let existing = existingByID[dto.id] {
                    existing.title = dto.title
                    existing.notes = dto.notes
                    existing.version = dto.version
                    existing.placementsJSON = placements
                    existing.audioJSON = audio
                    existing.createdAtMillis = dto.createdAt
                    existing.updatedAtMillis = dto.updatedAt
                } else {
                    modelContext.insert(StageModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) stages into SwiftData")
    }

    /// Remove stages not present in the provided set of ids (used for full reloads), so a stage
    /// deleted on another device disappears here too.
    func deleteAllExcept(ids: Set<StageIdentifier>) async throws {
        let all = try modelContext.fetch(FetchDescriptor<StageModel>())
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted stages not in provided id set; kept \(ids.count)")
    }
}
