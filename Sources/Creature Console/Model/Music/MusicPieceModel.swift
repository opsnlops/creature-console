import Common
import Foundation
import OSLog
import SwiftData

/// Local mirror of a saved music piece (server #202), kept in sync from the server through the
/// `music-piece-list` invalidation. Versions are stored as one JSON blob, like a dialog
/// script's turns: the editor always works on the whole piece, and a relationship graph would
/// only add upsert churn (see `DialogScriptModel`).
///
/// IMPORTANT: must stay in sync with `Common.SavedMusicPiece`.
@Model
final class MusicPieceModel: Identifiable {
    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicPieceModel")

    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var currentVersionIdString: String? = nil
    var versionsJSON: Data = Data("[]".utf8)
    var versionCount: Int = 0
    /// The current version's length, for the list.
    var currentDurationMillis: Int64 = 0
    var createdAtMillis: Int64 = 0
    var updatedAtMillis: Int64 = 0

    init(
        id: UUID, title: String, notes: String, currentVersionIdString: String?,
        versionsJSON: Data, versionCount: Int, currentDurationMillis: Int64,
        createdAtMillis: Int64, updatedAtMillis: Int64
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.currentVersionIdString = currentVersionIdString
        self.versionsJSON = versionsJSON
        self.versionCount = versionCount
        self.currentDurationMillis = currentDurationMillis
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
    }
}

extension MusicPieceModel {
    convenience init(dto: SavedMusicPiece) {
        let versions: Data
        do {
            versions = try JSONEncoder().encode(dto.versions)
        } catch {
            Self.logger.error(
                "Could not encode versions for music piece \(dto.id): \(error.localizedDescription)"
            )
            versions = Data("[]".utf8)
        }
        self.init(
            id: dto.id, title: dto.title, notes: dto.notes,
            currentVersionIdString: dto.currentVersionId?.uuidString.lowercased(),
            versionsJSON: versions, versionCount: dto.versions.count,
            currentDurationMillis: dto.currentVersion?.durationMilliseconds ?? 0,
            createdAtMillis: dto.createdAt, updatedAtMillis: dto.updatedAt)
    }

    func apply(dto: SavedMusicPiece) {
        title = dto.title
        notes = dto.notes
        currentVersionIdString = dto.currentVersionId?.uuidString.lowercased()
        do {
            versionsJSON = try JSONEncoder().encode(dto.versions)
        } catch {
            Self.logger.error(
                "Could not encode versions for music piece \(dto.id): \(error.localizedDescription)"
            )
        }
        versionCount = dto.versions.count
        currentDurationMillis = dto.currentVersion?.durationMilliseconds ?? 0
        createdAtMillis = dto.createdAt
        updatedAtMillis = dto.updatedAt
    }

    func toDTO() -> SavedMusicPiece {
        let versions: [SavedMusicVersion]
        do {
            versions = try JSONDecoder().decode([SavedMusicVersion].self, from: versionsJSON)
        } catch {
            Self.logger.error(
                "Could not decode versions for music piece \(self.id): \(error.localizedDescription)"
            )
            versions = []
        }
        return SavedMusicPiece(
            id: id, title: title, notes: notes, createdAt: createdAtMillis,
            updatedAt: updatedAtMillis,
            currentVersionId: currentVersionIdString.flatMap { UUID(uuidString: $0) },
            versions: versions)
    }

    var updatedAtDate: Date? {
        updatedAtMillis > 0 ? Date(timeIntervalSince1970: Double(updatedAtMillis) / 1_000) : nil
    }
}
