import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor DialogScriptImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogScriptImporter")

    /// Upsert a batch of DialogScript DTOs. Safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.DialogScript]) async throws {
        guard !dtos.isEmpty else { return }

        // Fetch all existing scripts in one query for efficiency
        let allExistingDescriptor = FetchDescriptor<DialogScriptModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                let encodedTurns = (try? JSONEncoder().encode(dto.turns)) ?? Data("[]".utf8)
                if let existing = existingByID[dto.id] {
                    // Update existing
                    existing.title = dto.title
                    existing.notes = dto.notes
                    existing.turnsJSON = encodedTurns
                    existing.createdAtMillis = dto.createdAt
                    existing.updatedAtMillis = dto.updatedAt
                } else {
                    // Insert new
                    modelContext.insert(DialogScriptModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) dialog scripts into SwiftData")
    }

    /// Remove scripts not present in the provided set of ids (used for full reloads).
    func deleteAllExcept(ids: Set<DialogScriptIdentifier>) async throws {
        let descriptor = FetchDescriptor<DialogScriptModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted dialog scripts not in provided id set; kept \(ids.count)")
    }
}
