import Common
import Foundation
import SwiftData

/// SwiftData model for Creature
///
/// **IMPORTANT**: This model must stay in sync with `Common.Creature` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
///
/// `inputs` are stored as a JSON-encoded `Data` blob rather than a child `@Relationship`.
/// A relationship would mean cache refreshes delete + recreate the child `InputModel`s, which
/// invalidates any of those objects the UI is still reading on the main context and crashes
/// with "backing data could no longer be found in the store". The whole creature is one
/// document from the server anyway, so a blob is the right fit (same approach as
/// `DmxFixtureModel` and `DialogScriptModel`).
@Model
final class CreatureModel {
    // Use creature ID as the unique identifier
    @Attribute(.unique) var id: String = ""
    var name: String = ""
    var channelOffset: Int = 0
    var mouthSlot: Int = 0
    var realData: Bool = false
    var audioChannel: Int = 0
    var speechLoopAnimationIds: [String] = []
    var idleAnimationIds: [String] = []
    var inputsJSON: Data = Data("[]".utf8)

    init(
        id: String, name: String, channelOffset: Int, mouthSlot: Int, realData: Bool,
        audioChannel: Int,
        inputs: [Common.Input],
        speechLoopAnimationIds: [String],
        idleAnimationIds: [String]
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.mouthSlot = mouthSlot
        self.realData = realData
        self.audioChannel = audioChannel
        self.inputsJSON = CreatureModel.encodeInputs(inputs)
        self.speechLoopAnimationIds = speechLoopAnimationIds
        self.idleAnimationIds = idleAnimationIds
    }
}

extension CreatureModel {

    /// Encode inputs to the stored blob. Best-effort: a failure falls back to an empty array so
    /// persistence never crashes on a transiently malformed input.
    static func encodeInputs(_ inputs: [Common.Input]) -> Data {
        (try? JSONEncoder().encode(inputs)) ?? Data("[]".utf8)
    }

    /// The inputs, decoded from the stored JSON blob.
    var inputs: [Common.Input] {
        (try? JSONDecoder().decode([Common.Input].self, from: inputsJSON)) ?? []
    }

    // Initialize from the Common DTO
    convenience init(dto: Common.Creature) {
        self.init(
            id: dto.id,
            name: dto.name,
            channelOffset: dto.channelOffset,
            mouthSlot: dto.mouthSlot,
            realData: dto.realData,
            audioChannel: dto.audioChannel,
            inputs: dto.inputs,
            speechLoopAnimationIds: dto.speechLoopAnimationIds,
            idleAnimationIds: dto.idleAnimationIds
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Creature {
        Common.Creature(
            id: id,
            name: name,
            channelOffset: channelOffset,
            mouthSlot: mouthSlot,
            audioChannel: audioChannel,
            inputs: inputs,
            realData: realData,
            speechLoopAnimationIds: speechLoopAnimationIds,
            idleAnimationIds: idleAnimationIds
        )
    }
}
