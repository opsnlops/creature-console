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
    // Embedded provenance (dialog renders). Defaulted so existing stores migrate cleanly.
    var title: String = ""
    var sourceScriptId: String = ""
    var script: String = ""
    var generationIds: String = ""
    var hasEmbeddedScript: Bool = false
    var hasEmbeddedLipsync: Bool = false

    init(
        id: SoundIdentifier, size: UInt32, transcript: String, lipsync: String,
        title: String = "", sourceScriptId: String = "", script: String = "",
        generationIds: String = "", hasEmbeddedScript: Bool = false,
        hasEmbeddedLipsync: Bool = false
    ) {
        self.id = id
        self.size = size
        self.transcript = transcript
        self.lipsync = lipsync
        self.title = title
        self.sourceScriptId = sourceScriptId
        self.script = script
        self.generationIds = generationIds
        self.hasEmbeddedScript = hasEmbeddedScript
        self.hasEmbeddedLipsync = hasEmbeddedLipsync
    }
}

extension SoundModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Sound) {
        self.init(
            id: dto.fileName,
            size: dto.size,
            transcript: dto.transcript,
            lipsync: dto.lipsync,
            title: dto.title,
            sourceScriptId: dto.sourceScriptId,
            script: dto.script,
            generationIds: dto.generationIds,
            hasEmbeddedScript: dto.hasEmbeddedScript,
            hasEmbeddedLipsync: dto.hasEmbeddedLipsync
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Sound {
        Common.Sound(
            fileName: id, size: size, transcript: transcript, lipsync: lipsync,
            title: title, sourceScriptId: sourceScriptId, script: script,
            generationIds: generationIds, hasEmbeddedScript: hasEmbeddedScript,
            hasEmbeddedLipsync: hasEmbeddedLipsync)
    }
}
