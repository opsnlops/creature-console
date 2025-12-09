import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor CreatureImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreatureImporter")

    // Upsert a batch of Creature DTOs. This is safe to call repeatedly with overlapping data.
    func upsertBatch(_ dtos: [Common.Creature]) async throws {
        guard !dtos.isEmpty else { return }

        // Fetch all existing creatures in one query for efficiency
        let allExistingDescriptor = FetchDescriptor<CreatureModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        try modelContext.transaction {
            for dto in dtos {
                if let existing = existingByID[dto.id] {
                    // Update existing
                    existing.name = dto.name
                    existing.channelOffset = dto.channelOffset
                    existing.mouthSlot = dto.mouthSlot
                    existing.realData = dto.realData
                    existing.audioChannel = dto.audioChannel
                    existing.speechLoopAnimationIds = dto.speechLoopAnimationIds
                    existing.idleAnimationIds = dto.idleAnimationIds

                    // Update inputs: explicitly delete old ones before adding new ones
                    for input in existing.inputs {
                        modelContext.delete(input)
                    }
                    existing.inputs = dto.inputs.map { InputModel(dto: $0) }
                } else {
                    // Insert new
                    modelContext.insert(CreatureModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) creatures into SwiftData")
    }

    // Remove creatures not present in the provided set of ids (optional helper for full reloads)
    func deleteAllExcept(ids: Set<String>) async throws {
        let descriptor = FetchDescriptor<CreatureModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted creatures not in provided id set; kept \(ids.count)")
    }
}
