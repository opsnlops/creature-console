import Foundation

public struct CreatureConfigValidationDTO: Codable, Sendable, Equatable {
    public var valid: Bool
    public var creatureId: String?
    public var missingAnimationIds: [String]
    public var mismatchedAnimationIds: [String]
    public var errorMessages: [String]

    enum CodingKeys: String, CodingKey {
        case valid
        case creatureId = "creature_id"
        case missingAnimationIds = "missing_animation_ids"
        case mismatchedAnimationIds = "mismatched_animation_ids"
        case errorMessages = "error_messages"
    }

    public init(
        valid: Bool,
        creatureId: String? = nil,
        missingAnimationIds: [String] = [],
        mismatchedAnimationIds: [String] = [],
        errorMessages: [String] = []
    ) {
        self.valid = valid
        self.creatureId = creatureId
        self.missingAnimationIds = missingAnimationIds
        self.mismatchedAnimationIds = mismatchedAnimationIds
        self.errorMessages = errorMessages
    }
}
