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
    var backgroundMusicJSON: Data? = nil
    /// The accepted voice take, JSON-encoded like the music blob. Must round-trip — dropping it
    /// would make an edit through the cache lose the acceptance the render gate depends on.
    var acceptedVoiceJSON: Data? = nil
    /// The script's usual stage, stored as a string so SwiftData needs no schema knowledge of
    /// UUIDs; nil = unbound. Must round-trip faithfully — dropping it here would make an edit
    /// through the cache silently clear the binding on save.
    var stageIdString: String? = nil
    var createdAtMillis: Int64? = nil
    var updatedAtMillis: Int64? = nil

    init(
        id: DialogScriptIdentifier,
        title: String,
        notes: String,
        turnsJSON: Data,
        backgroundMusicJSON: Data?,
        acceptedVoiceJSON: Data?,
        stageIdString: String?,
        createdAtMillis: Int64?,
        updatedAtMillis: Int64?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.turnsJSON = turnsJSON
        self.backgroundMusicJSON = backgroundMusicJSON
        self.acceptedVoiceJSON = acceptedVoiceJSON
        self.stageIdString = stageIdString
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
    }
}

extension DialogScriptModel {

    convenience init(dto: Common.DialogScript) {
        // These DTOs are already validated Codable values. Encoding failures indicate a
        // programming/schema error and should not silently turn a real script into an empty one.
        var turns: Data
        var backgroundMusic: Data?
        var acceptedVoice: Data?
        do {
            turns = try JSONEncoder().encode(dto.turns)
            backgroundMusic = try dto.backgroundMusic.map { try JSONEncoder().encode($0) }
            acceptedVoice = try dto.acceptedVoice.map { try JSONEncoder().encode($0) }
        } catch {
            Self.logger.fault(
                "Could not encode dialog script \(dto.id): \(error.localizedDescription)")
            turns = Data("[]".utf8)
            backgroundMusic = nil
            acceptedVoice = nil
        }
        self.init(
            id: dto.id,
            title: dto.title,
            notes: dto.notes,
            turnsJSON: turns,
            backgroundMusicJSON: backgroundMusic,
            acceptedVoiceJSON: acceptedVoice,
            stageIdString: dto.stageId?.uuidString.lowercased(),
            createdAtMillis: dto.createdAt,
            updatedAtMillis: dto.updatedAt
        )
    }

    /// Convert back to the Common DTO. Decoding the blob can in principle fail (e.g. if the
    /// on-disk JSON predates a future model change); log the corruption rather than silently
    /// presenting an apparently valid but empty script.
    func toDTO() -> Common.DialogScript {
        let turns: [DialogScriptTurn]
        do {
            turns = try JSONDecoder().decode([DialogScriptTurn].self, from: turnsJSON)
        } catch {
            Self.logger.error(
                "Could not decode turns for dialog script \(self.id): \(error.localizedDescription)"
            )
            turns = []
        }
        let backgroundMusic: DialogBackgroundMusic?
        if let backgroundMusicJSON {
            do {
                backgroundMusic = try JSONDecoder().decode(
                    DialogBackgroundMusic.self, from: backgroundMusicJSON)
            } catch {
                Self.logger.error(
                    "Could not decode background music for dialog script \(self.id): \(error.localizedDescription)"
                )
                backgroundMusic = nil
            }
        } else {
            backgroundMusic = nil
        }
        return Common.DialogScript(
            id: id,
            title: title,
            notes: notes,
            turns: turns,
            backgroundMusic: backgroundMusic,
            acceptedVoice: acceptedVoiceJSON.flatMap {
                try? JSONDecoder().decode(DialogAcceptedVoice.self, from: $0)
            },
            stageId: stageIdString.flatMap { UUID(uuidString: $0) },
            createdAt: createdAtMillis,
            updatedAt: updatedAtMillis
        )
    }

    /// Convenience for the table view — derive the turn count without round-tripping the
    /// whole DTO.
    var turnCount: Int {
        (try? JSONDecoder().decode([DialogScriptTurn].self, from: turnsJSON))?.count ?? 0
    }

    var hasBackgroundMusic: Bool { backgroundMusicJSON != nil }

    var updatedAtDate: Date? {
        updatedAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    var createdAtDate: Date? {
        createdAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}
