import Common
import Foundation
import SwiftData

/// SwiftData model for persisted sound metadata.
///
/// **IMPORTANT**: Keep fields in sync with `Common.Sound` DTO.
@Model
final class SoundModel: Identifiable {
    // Use file name as the unique identifier to match server semantics
    @Attribute(.unique) var id: SoundIdentifier = ""
    var size: UInt32 = 0
    var transcript: String = ""
    var lipsync: String = ""

    init(id: SoundIdentifier, size: UInt32, transcript: String, lipsync: String) {
        self.id = id
        self.size = size
        self.transcript = transcript
        self.lipsync = lipsync
    }
}

extension SoundModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Sound) {
        self.init(
            id: dto.fileName,
            size: dto.size,
            transcript: dto.transcript,
            lipsync: dto.lipsync
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Sound {
        Common.Sound(fileName: id, size: size, transcript: transcript, lipsync: lipsync)
    }
}
