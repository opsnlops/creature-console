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
                let encodedTurns = try JSONEncoder().encode(dto.turns)
                let encodedMusic = try dto.backgroundMusic.map { try JSONEncoder().encode($0) }
                if let existing = existingByID[dto.id] {
                    // Update existing
                    existing.title = dto.title
                    existing.notes = dto.notes
                    existing.turnsJSON = encodedTurns
                    existing.backgroundMusicJSON = encodedMusic
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

    /// Returns the ids currently known locally. The server's dialog-script invalidation is a
    /// collection hint without an id, while the deployed API exposes parameterized reads. Keep
    /// the ids from our local cache so an invalidation can still refresh the saved scripts without
    /// issuing an invalid unparameterized collection request.
    func allIDs() async throws -> [DialogScriptIdentifier] {
        let descriptor = FetchDescriptor<DialogScriptModel>()
        return try modelContext.fetch(descriptor).map(\.id)
    }

    /// Removes one locally cached script after its parameterized server read returns 404.
    func delete(id: DialogScriptIdentifier) throws {
        let descriptor = FetchDescriptor<DialogScriptModel>(
            predicate: #Predicate { $0.id == id }
        )
        for model in try modelContext.fetch(descriptor) {
            modelContext.delete(model)
        }
        try modelContext.save()
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
