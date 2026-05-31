import Common
import Foundation
import OSLog
import SwiftData

/// SwiftData model for a saved storyboard.
///
/// **IMPORTANT**: keep in sync with `Common.Storyboard`. Tiles are stored as a JSON-encoded `Data`
/// blob (not a `@Relationship`) — the whole card is one document, and a relationship graph would
/// invalidate child objects the UI is reading on a cache refresh (the `InputModel` crash class). Same
/// approach as `DialogScriptModel` / `DmxFixtureModel`. Timestamps are raw epoch-ms `Int64?`.
@Model
final class StoryboardModel: Identifiable {

    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardModel")

    @Attribute(.unique) var id: StoryboardIdentifier = UUID()
    var title: String = ""
    var notes: String = ""
    var tilesJSON: Data = Data("[]".utf8)
    var createdAtMillis: Int64? = nil
    var updatedAtMillis: Int64? = nil

    init(
        id: StoryboardIdentifier,
        title: String,
        notes: String,
        tilesJSON: Data,
        createdAtMillis: Int64?,
        updatedAtMillis: Int64?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.tilesJSON = tilesJSON
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
    }
}

extension StoryboardModel {

    convenience init(dto: Common.Storyboard) {
        let tiles = (try? JSONEncoder().encode(dto.tiles)) ?? Data("[]".utf8)
        self.init(
            id: dto.id,
            title: dto.title,
            notes: dto.notes,
            tilesJSON: tiles,
            createdAtMillis: dto.createdAt,
            updatedAtMillis: dto.updatedAt
        )
    }

    /// Convert back to the Common DTO. Decoding the blob can fail (e.g. on-disk JSON predating a
    /// model change); surface an empty array rather than crashing the UI.
    func toDTO() -> Common.Storyboard {
        let tiles =
            (try? JSONDecoder().decode([StoryboardTile].self, from: tilesJSON)) ?? []
        return Common.Storyboard(
            id: id,
            title: title,
            notes: notes,
            tiles: tiles,
            createdAt: createdAtMillis,
            updatedAt: updatedAtMillis
        )
    }

    /// Convenience for the table view — derive the tile count without round-tripping the DTO.
    var tileCount: Int {
        (try? JSONDecoder().decode([StoryboardTile].self, from: tilesJSON))?.count ?? 0
    }

    var updatedAtDate: Date? {
        updatedAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    var createdAtDate: Date? {
        createdAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}
