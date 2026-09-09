import Foundation
import MongoKitten
import WorldCore

struct SourceCheckpoint: Codable, Equatable, Sendable {
    let sourceID: SourceID
    var value: WorldJSONValue
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case value
        case updatedAt = "updated_at"
    }
}

struct SourceCheckpointRepository: Sendable {
    private let checkpoints: MongoCollection

    init(database: MongoDatabase) {
        self.checkpoints = database[MongoWorldCollection.sourceCheckpoints]
    }

    func save(_ checkpoint: SourceCheckpoint) async throws {
        var document = try BSONEncoder().encode(checkpoint)
        document["_id"] = checkpoint.sourceID.rawValue
        _ = try await checkpoints.findOneAndUpsert(
            where: ["_id": checkpoint.sourceID.rawValue],
            replacement: document,
            returnValue: .modified
        )
        .writeConcern(.majority())
        .execute()
    }

    func checkpoint(for sourceID: SourceID) async throws -> SourceCheckpoint? {
        try await checkpoints.findOne(
            ["source_id": sourceID.rawValue],
            as: SourceCheckpoint.self
        )
    }
}
