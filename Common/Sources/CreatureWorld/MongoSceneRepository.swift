import Foundation
import MongoKitten
import WorldCore

/// Durable scenes, keyed by scene ID: the record of who spoke, in what order, and how it played.
struct MongoSceneRepository: SceneRepository, Sendable {
    private let scenes: MongoCollection

    init(database: MongoDatabase) {
        scenes = database[MongoWorldCollection.scenes]
    }

    func scene(id: SceneID) async throws -> Scene? {
        try await scenes.findOne(["_id": id.rawValue], as: Scene.self)
    }

    func save(_ scene: Scene) async throws {
        var document = try BSONEncoder().encode(scene)
        document["_id"] = scene.sceneID.rawValue
        try await scenes.upsert(document, where: ["_id": scene.sceneID.rawValue])
    }

    func openScenes(in regionID: EntityID) async throws -> [Scene] {
        try await scenes.find(
            ["region_id": regionID.rawValue, "state": SceneState.open.rawValue], as: Scene.self
        )
        .sort(["opened_at": 1])
        .drain()
    }

    func recentScenes(limit: Int) async throws -> [Scene] {
        precondition(limit > 0)
        return try await scenes.find(as: Scene.self)
            .sort(["opened_at": -1, "_id": -1])
            .limit(limit)
            .drain()
    }
}
