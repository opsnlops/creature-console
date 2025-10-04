import Common
import Foundation
import SwiftData

/// SwiftData model for Creature
///
/// **IMPORTANT**: This model must stay in sync with `Common.Creature` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class CreatureModel {
    // Use creature ID as the unique identifier
    @Attribute(.unique) var id: String = ""
    var name: String = ""
    var channelOffset: Int = 0
    var realData: Bool = false
    var audioChannel: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \InputModel.creature)
    var inputs: [InputModel] = []

    init(
        id: String, name: String, channelOffset: Int, realData: Bool, audioChannel: Int,
        inputs: [InputModel]
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.realData = realData
        self.audioChannel = audioChannel
        self.inputs = inputs
    }
}

extension CreatureModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Creature) {
        let inputModels = dto.inputs.map { InputModel(dto: $0) }
        self.init(
            id: dto.id,
            name: dto.name,
            channelOffset: dto.channelOffset,
            realData: dto.realData,
            audioChannel: dto.audioChannel,
            inputs: inputModels
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Creature {
        let inputDTOs = inputs.map { $0.toDTO() }
        return Common.Creature(
            id: id,
            name: name,
            channelOffset: channelOffset,
            audioChannel: audioChannel,
            inputs: inputDTOs,
            realData: realData
        )
    }
}
