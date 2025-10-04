import Common
import Foundation
import SwiftData

/// SwiftData model for AnimationMetadata
///
/// **IMPORTANT**: This model must stay in sync with `Common.AnimationMetadata` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class AnimationMetadataModel: Identifiable {
    // Use animation ID as the unique identifier
    @Attribute(.unique) var id: AnimationIdentifier = ""
    var title: String = ""
    var lastUpdated: Date? = nil
    var millisecondsPerFrame: UInt32 = 20
    var note: String = ""
    var soundFile: String = ""
    var numberOfFrames: UInt32 = 0
    var multitrackAudio: Bool = false

    init(
        id: AnimationIdentifier, title: String, lastUpdated: Date?, millisecondsPerFrame: UInt32,
        note: String, soundFile: String, numberOfFrames: UInt32, multitrackAudio: Bool
    ) {
        self.id = id
        self.title = title
        self.lastUpdated = lastUpdated
        self.millisecondsPerFrame = millisecondsPerFrame
        self.note = note
        self.soundFile = soundFile
        self.numberOfFrames = numberOfFrames
        self.multitrackAudio = multitrackAudio
    }
}

extension AnimationMetadataModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.AnimationMetadata) {
        self.init(
            id: dto.id,
            title: dto.title,
            lastUpdated: dto.lastUpdated,
            millisecondsPerFrame: dto.millisecondsPerFrame,
            note: dto.note,
            soundFile: dto.soundFile,
            numberOfFrames: dto.numberOfFrames,
            multitrackAudio: dto.multitrackAudio
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.AnimationMetadata {
        Common.AnimationMetadata(
            id: id,
            title: title,
            lastUpdated: lastUpdated ?? Date(),
            millisecondsPerFrame: millisecondsPerFrame,
            note: note,
            soundFile: soundFile,
            numberOfFrames: numberOfFrames,
            multitrackAudio: multitrackAudio
        )
    }
}
