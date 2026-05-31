import Common
import Foundation
import OSLog
import SwiftData

/// SwiftData model for a saved multi-character dialog script.
///
/// **IMPORTANT**: this model must stay in sync with `Common.DialogScript`. The script's
/// `turns` are stored as a JSON-encoded `Data` blob rather than a `@Relationship` graph —
/// the editor always works on the whole script as a unit and the wire format is one
/// document, so a relationship graph would only add upsert complexity (mirrors the
/// approach in `DmxFixtureModel`).
///
/// Timestamps are stored as raw epoch milliseconds (`Int64?`), exactly as they arrive on
/// the wire — this is lossless and lets `@Query` sort newest-first on `updatedAtMillis`
/// without any date-strategy ambiguity.
@Model
final class DialogScriptModel: Identifiable {

    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogScriptModel")

    @Attribute(.unique) var id: DialogScriptIdentifier = UUID()
    var title: String = ""
    var notes: String = ""
    var turnsJSON: Data = Data("[]".utf8)
    var createdAtMillis: Int64? = nil
    var updatedAtMillis: Int64? = nil

    init(
        id: DialogScriptIdentifier,
        title: String,
        notes: String,
        turnsJSON: Data,
        createdAtMillis: Int64?,
        updatedAtMillis: Int64?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.turnsJSON = turnsJSON
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
    }
}

extension DialogScriptModel {

    convenience init(dto: Common.DialogScript) {
        // Best-effort encode — failures fall back to an empty array so SwiftData persistence
        // doesn't crash on a transiently malformed turn.
        let turns = (try? JSONEncoder().encode(dto.turns)) ?? Data("[]".utf8)
        self.init(
            id: dto.id,
            title: dto.title,
            notes: dto.notes,
            turnsJSON: turns,
            createdAtMillis: dto.createdAt,
            updatedAtMillis: dto.updatedAt
        )
    }

    /// Convert back to the Common DTO. Decoding the blob can in principle fail (e.g. if the
    /// on-disk JSON predates a future model change); we surface an empty array rather than
    /// crashing the UI.
    func toDTO() -> Common.DialogScript {
        let turns =
            (try? JSONDecoder().decode([DialogScriptTurn].self, from: turnsJSON)) ?? []
        return Common.DialogScript(
            id: id,
            title: title,
            notes: notes,
            turns: turns,
            createdAt: createdAtMillis,
            updatedAt: updatedAtMillis
        )
    }

    /// Convenience for the table view — derive the turn count without round-tripping the
    /// whole DTO.
    var turnCount: Int {
        (try? JSONDecoder().decode([DialogScriptTurn].self, from: turnsJSON))?.count ?? 0
    }

    var updatedAtDate: Date? {
        updatedAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    var createdAtDate: Date? {
        createdAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}
