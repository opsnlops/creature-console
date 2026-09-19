import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor MusicPieceImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicPieceImporter")

    /// Upsert a batch of saved pieces. Existing rows are mutated in place so object identity
    /// (and any selection bound to it) survives a refresh.
    func upsertBatch(_ dtos: [SavedMusicPiece]) async throws {
        guard !dtos.isEmpty else { return }
        let allExisting = try modelContext.fetch(FetchDescriptor<MusicPieceModel>())
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })
        try modelContext.transaction {
            for dto in dtos {
                if let existing = existingByID[dto.id] {
                    existing.apply(dto: dto)
                } else {
                    modelContext.insert(MusicPieceModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) music pieces into SwiftData")
    }

    /// Remove pieces not present in the provided set of ids (used for full reloads).
    func deleteAllExcept(ids: Set<UUID>) async throws {
        let all = try modelContext.fetch(FetchDescriptor<MusicPieceModel>())
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted music pieces not in provided id set; kept \(ids.count)")
    }

    /// Removes one piece after the server confirmed its deletion.
    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<MusicPieceModel>(predicate: #Predicate { $0.id == id })
        for model in try modelContext.fetch(descriptor) {
            modelContext.delete(model)
        }
        try modelContext.save()
    }
}
