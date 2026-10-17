import Foundation
import MongoKitten
import WorldCore

/// `house_scenes`: one document per scene name, saying what the scene is and whether a bird may
/// ask for it (#241). Seeded from the config's drafts; a Wizard's word is never overwritten.
struct HouseSceneRepository: Sendable {
    private let scenes: MongoCollection

    init(database: MongoDatabase) {
        self.scenes = database[MongoWorldCollection.houseScenes]
    }

    static let draftEditor = "world:draft"

    /// Writes every draft that has no document yet, and replaces the ones a draft wrote when
    /// the draft has changed; a scene April described is left alone - the fact-meanings rule.
    func seed(_ drafts: [String: HouseSceneDraft], at now: Date) async throws {
        for (name, draft) in drafts {
            let insert: Document = [
                "name": name, "description": draft.description, "askable": draft.askable,
                "updated_at": now, "updated_by": Self.draftEditor,
            ]
            try await scenes.upsert(["$setOnInsert": insert], where: ["_id": name])
            let stale: Document = [
                "_id": name, "updated_by": Self.draftEditor,
                "$or": [
                    ["description": ["$ne": draft.description] as Document],
                    ["askable": ["$ne": draft.askable] as Document],
                ] as [Document],
            ]
            _ = try await scenes.updateOne(
                where: stale,
                to: [
                    "$set": [
                        "description": draft.description, "askable": draft.askable,
                        "updated_at": now,
                    ] as Document
                ])
        }
    }

    /// Every described scene, by name.
    func all() async throws -> [String: HouseScene] {
        let documents = try await scenes.find([:]).drain()
        return Dictionary(
            try documents.map(decode).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func set(_ name: String, _ update: HouseSceneUpdate, at now: Date) async throws -> HouseScene {
        let document: Document = [
            "_id": name, "name": name, "description": update.description,
            "askable": update.askable, "updated_at": now, "updated_by": update.updatedBy,
        ]
        try await scenes.upsert(document, where: ["_id": name])
        return HouseScene(
            name: name, description: update.description, askable: update.askable,
            updatedAt: now, updatedBy: update.updatedBy)
    }

    private func decode(_ document: Document) throws -> HouseScene {
        HouseScene(
            name: document["name"] as? String ?? (document["_id"] as? String ?? ""),
            description: document["description"] as? String ?? "",
            askable: document["askable"] as? Bool ?? true,
            updatedAt: document["updated_at"] as? Date,
            updatedBy: document["updated_by"] as? String)
    }
}

/// A scene as the config drafts it: `"Sleepy Time": {"description": "…", "askable": true}`.
struct HouseSceneDraft: Codable, Equatable, Sendable {
    var description: String
    var askable: Bool

    init(description: String, askable: Bool = true) {
        self.description = description
        self.askable = askable
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        askable = try container.decodeIfPresent(Bool.self, forKey: .askable) ?? true
    }

    enum CodingKeys: String, CodingKey { case description, askable }
}
