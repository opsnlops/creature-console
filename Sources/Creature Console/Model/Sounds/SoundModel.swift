import Common
import Foundation
import SwiftData

@Model
final class SoundModel: Identifiable {
    // Use file name as the unique identifier to match server semantics
    @Attribute(.unique) var id: SoundIdentifier = ""
    var size: UInt32 = 0
    var transcript: String = ""

    init(id: SoundIdentifier, size: UInt32, transcript: String) {
        self.id = id
        self.size = size
        self.transcript = transcript
    }
}

extension SoundModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Sound) {
        self.init(id: dto.fileName, size: dto.size, transcript: dto.transcript)
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Sound {
        Common.Sound(fileName: id, size: size, transcript: transcript)
    }
}
