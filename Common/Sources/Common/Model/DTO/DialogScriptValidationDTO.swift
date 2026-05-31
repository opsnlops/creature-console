import Foundation

/// Response body for `POST /api/v1/animation/dialog/script/validate`.
///
/// Always returned with HTTP `200` — even for invalid payloads — so the editor can render
/// inline form errors without try/catch. `missingCreatureIds` are **soft warnings** (the
/// referenced creatures aren't registered yet; render will fail) and do *not* flip `valid`
/// to false. `errorMessages` are hard validation errors and are empty when `valid == true`.
public struct DialogScriptValidationDTO: Codable, Sendable, Equatable {

    public var valid: Bool
    public var scriptId: String?
    public var turnCount: UInt32
    public var missingCreatureIds: [String]
    public var errorMessages: [String]

    enum CodingKeys: String, CodingKey {
        case valid
        case scriptId = "script_id"
        case turnCount = "turn_count"
        case missingCreatureIds = "missing_creature_ids"
        case errorMessages = "error_messages"
    }

    public init(
        valid: Bool,
        scriptId: String? = nil,
        turnCount: UInt32 = 0,
        missingCreatureIds: [String] = [],
        errorMessages: [String] = []
    ) {
        self.valid = valid
        self.scriptId = scriptId
        self.turnCount = turnCount
        self.missingCreatureIds = missingCreatureIds
        self.errorMessages = errorMessages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        valid = try container.decode(Bool.self, forKey: .valid)
        scriptId = try container.decodeIfPresent(String.self, forKey: .scriptId)
        turnCount = try container.decodeIfPresent(UInt32.self, forKey: .turnCount) ?? 0
        missingCreatureIds =
            try container.decodeIfPresent([String].self, forKey: .missingCreatureIds) ?? []
        errorMessages =
            try container.decodeIfPresent([String].self, forKey: .errorMessages) ?? []
    }
}
