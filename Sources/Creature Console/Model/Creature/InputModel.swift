import Common
import Foundation
import SwiftData

/// SwiftData model for Input
///
/// **IMPORTANT**: This model must stay in sync with `Common.Input` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class InputModel {
    var name: String = ""
    var slot: UInt16 = 0
    var width: UInt8 = 0
    var joystickAxis: UInt8 = 0

    // Inverse relationship back to the creature that owns this input
    var creature: CreatureModel?

    init(name: String, slot: UInt16, width: UInt8, joystickAxis: UInt8) {
        self.name = name
        self.slot = slot
        self.width = width
        self.joystickAxis = joystickAxis
    }
}

extension InputModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Input) {
        self.init(name: dto.name, slot: dto.slot, width: dto.width, joystickAxis: dto.joystickAxis)
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Input {
        Common.Input(name: name, slot: slot, width: width, joystickAxis: joystickAxis)
    }
}
