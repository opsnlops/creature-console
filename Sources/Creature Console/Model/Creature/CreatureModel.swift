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
    var audioChannel: Int = 0
    /// Names the input that drives the mouth, overriding `mouthSlot`. Optional with a default,
    /// so it's a lightweight SwiftData migration.
    var mouthInput: String? = nil
    var speechLoopAnimationIds: [String] = []
    var idleAnimationIds: [String] = []
    var inputsJSON: Data = Data("[]".utf8)
    /// Head-aiming config, stored as a JSON blob for the same reason `inputs` is: it's one
    /// nested document from the server, and a child relationship would churn on every refresh.
    /// Empty data means no gaze configured.
    var gazeJSON: Data = Data()

    init(
        id: String, name: String, channelOffset: Int, mouthSlot: Int,
        audioChannel: Int,
        inputs: [Common.Input],
        mouthInput: String? = nil,
        speechLoopAnimationIds: [String],
        idleAnimationIds: [String],
        gaze: Common.GazeConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.mouthSlot = mouthSlot
        self.audioChannel = audioChannel
        self.inputsJSON = CreatureModel.encodeInputs(inputs)
        self.mouthInput = mouthInput
        self.speechLoopAnimationIds = speechLoopAnimationIds
        self.idleAnimationIds = idleAnimationIds
        self.gazeJSON = CreatureModel.encodeGaze(gaze)
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

    /// Encode gaze to the stored blob. A creature with no gaze stores empty data rather than
    /// an empty object, so "no head aiming" survives the round trip as absence.
    static func encodeGaze(_ gaze: Common.GazeConfig?) -> Data {
        guard let gaze, !gaze.isEmpty, let encoded = try? JSONEncoder().encode(gaze) else {
            return Data()
        }
        return encoded
    }

    /// The head-aiming config, decoded from the stored JSON blob, or `nil` when there is none.
    var gaze: Common.GazeConfig? {
        guard !gazeJSON.isEmpty,
            let decoded = try? JSONDecoder().decode(Common.GazeConfig.self, from: gazeJSON),
            !decoded.isEmpty
        else { return nil }
        return decoded
    }

    // Initialize from the Common DTO
    convenience init(dto: Common.Creature) {
        self.init(
            id: dto.id,
            name: dto.name,
            channelOffset: dto.channelOffset,
            mouthSlot: dto.mouthSlot,
            audioChannel: dto.audioChannel,
            inputs: dto.inputs,
            mouthInput: dto.mouthInput,
            speechLoopAnimationIds: dto.speechLoopAnimationIds,
            idleAnimationIds: dto.idleAnimationIds,
            gaze: dto.gaze
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
            mouthInput: mouthInput,
            speechLoopAnimationIds: speechLoopAnimationIds,
            idleAnimationIds: idleAnimationIds,
            gaze: gaze
        )
    }
}
