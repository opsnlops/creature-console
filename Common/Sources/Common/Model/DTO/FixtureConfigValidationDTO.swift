import Foundation

/// Response body for `POST /api/v1/fixture/validate`. `missingCreatureIds` are
/// soft warnings — bindings pointing at missing creatures still save (the dispatcher
/// simply won't fire). `errorMessages` are hard blockers.
public struct FixtureConfigValidationDTO: Codable, Sendable, Equatable {
    public var valid: Bool
    public var fixtureId: String?
    public var missingCreatureIds: [String]
    public var errorMessages: [String]

    enum CodingKeys: String, CodingKey {
        case valid
        case fixtureId = "fixture_id"
        case missingCreatureIds = "missing_creature_ids"
        case errorMessages = "error_messages"
    }

    public init(
        valid: Bool,
        fixtureId: String? = nil,
        missingCreatureIds: [String] = [],
        errorMessages: [String] = []
    ) {
        self.valid = valid
        self.fixtureId = fixtureId
        self.missingCreatureIds = missingCreatureIds
        self.errorMessages = errorMessages
    }
}
