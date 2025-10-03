import Foundation
import SwiftData
import Common
import OSLog

@ModelActor
actor SoundImporter {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundImporter")

    // Upsert a batch of Sound DTOs. This is safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Sound]) async throws {
        guard !dtos.isEmpty else { return }
        try modelContext.transaction {
            for dto in dtos {
                let fileName = dto.fileName
                // Fetch existing by unique id
                var descriptor = FetchDescriptor<SoundModel>(
                    predicate: #Predicate { $0.id == fileName }
                )
                descriptor.fetchLimit = 1
                let existing = try? modelContext.fetch(descriptor).first
                if let model = existing {
                    model.size = dto.size
                    model.transcript = dto.transcript
                } else {
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

