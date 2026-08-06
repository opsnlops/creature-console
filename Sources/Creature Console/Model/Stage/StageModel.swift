import Common
import Foundation
import OSLog
import SwiftData

/// SwiftData model for a saved stage.
///
/// **IMPORTANT**: keep in sync with `Common.Stage`. Placements and the audio block are stored as
/// JSON-encoded `Data` blobs rather than `@Relationship` children — a stage is one document, and a
/// relationship graph would invalidate child objects the UI is reading on a cache refresh (the
/// `InputModel` crash class). Same approach as `StoryboardModel` / `DialogScriptModel`. Timestamps
/// are raw epoch-ms `Int64?`.
///
/// Storing the blobs verbatim also preserves the extra keys the server round-trips for us, so a
/// stage written by a newer client survives a trip through this one's cache.
@Model
final class StageModel: Identifiable {

    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StageModel")

    @Attribute(.unique) var id: StageIdentifier = UUID()
    var title: String = ""
    var notes: String = ""
    var version: Int = StageLimits.currentVersion
    var placementsJSON: Data = Data("[]".utf8)
    var audioJSON: Data = Data("{}".utf8)
    var createdAtMillis: Int64? = nil
    var updatedAtMillis: Int64? = nil

    init(
        id: StageIdentifier,
        title: String,
        notes: String,
        version: Int,
        placementsJSON: Data,
        audioJSON: Data,
        createdAtMillis: Int64?,
        updatedAtMillis: Int64?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.version = version
        self.placementsJSON = placementsJSON
        self.audioJSON = audioJSON
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
    }

    /// How many creatures are placed, without paying to decode the whole blob for a list row.
    var placementCount: Int {
        (try? JSONDecoder().decode([StagePlacement].self, from: placementsJSON))?.count ?? 0
    }

    var updatedAtDate: Date? {
        updatedAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}

extension StageModel {

    convenience init(dto: Common.Stage) {
        self.init(
            id: dto.id,
            title: dto.title,
            notes: dto.notes,
            version: dto.version,
            placementsJSON: (try? JSONEncoder().encode(dto.placements)) ?? Data("[]".utf8),
            audioJSON: (try? JSONEncoder().encode(dto.audio)) ?? Data("{}".utf8),
            createdAtMillis: dto.createdAt,
            updatedAtMillis: dto.updatedAt
        )
    }

    /// Convert back to the Common DTO. Decoding a blob can fail (e.g. on-disk JSON predating a
    /// model change); fall back to sane empties rather than crashing the UI.
    func toDTO() -> Common.Stage {
        let placements =
            (try? JSONDecoder().decode([StagePlacement].self, from: placementsJSON)) ?? []
        let audio =
            (try? JSONDecoder().decode(StageAudioSettings.self, from: audioJSON))
            ?? StageAudioSettings()
        return Common.Stage(
            id: id,
            title: title,
            notes: notes,
            version: version,
            placements: placements,
            audio: audio,
            createdAt: createdAtMillis,
            updatedAt: updatedAtMillis
        )
    }
}
