import Foundation

public struct FactProducer: Hashable, Sendable, Codable {
    public var kind: String
    public var id: String
    public var version: String

    public init(kind: String, id: String, version: String) {
        self.kind = kind
        self.id = id
        self.version = version
    }
}

public struct Fact: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var factID: FactID
    public var subjectID: EntityID
    public var predicate: String
    public var value: WorldJSONValue
    public var epistemic: EpistemicState
    public var validFrom: Date
    public var validTo: Date?
    public var derivedFrom: [ProvenanceReference]
    public var producer: FactProducer
    public var supersededBy: FactID?

    public init(
        factID: FactID = .generated(),
        subjectID: EntityID,
        predicate: String,
        value: WorldJSONValue,
        epistemic: EpistemicState,
        validFrom: Date,
        validTo: Date? = nil,
        derivedFrom: [ProvenanceReference],
        producer: FactProducer,
        supersededBy: FactID? = nil
    ) throws {
        if let validTo, validTo < validFrom {
            throw WorldContractError.invalidDateInterval
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.factID = factID
        self.subjectID = subjectID
        self.predicate = predicate
        self.value = value
        self.epistemic = epistemic
        self.validFrom = validFrom
        self.validTo = validTo
        self.derivedFrom = derivedFrom
        self.producer = producer
        self.supersededBy = supersededBy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        let validFrom = try container.decode(Date.self, forKey: .validFrom)
        let validTo = try container.decodeIfPresent(Date.self, forKey: .validTo)
        if let validTo, validTo < validFrom {
            throw WorldContractError.invalidDateInterval
        }
        self.schemaVersion = schemaVersion
        self.factID = try container.decode(FactID.self, forKey: .factID)
        self.subjectID = try container.decode(EntityID.self, forKey: .subjectID)
        self.predicate = try container.decode(String.self, forKey: .predicate)
        // A `null` value ("Beaky has left") is dropped by some encoders (BSON); a fact with
        // no value key means null, wherever it was stored — in the facts collection or inside
        // a percept.
        self.value = try container.decodeIfPresent(WorldJSONValue.self, forKey: .value) ?? .null
        self.epistemic = try container.decode(EpistemicState.self, forKey: .epistemic)
        self.validFrom = validFrom
        self.validTo = validTo
        self.derivedFrom = try container.decode(
            [ProvenanceReference].self,
            forKey: .derivedFrom
        )
        self.producer = try container.decode(FactProducer.self, forKey: .producer)
        self.supersededBy = try container.decodeIfPresent(FactID.self, forKey: .supersededBy)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case factID = "fact_id"
        case subjectID = "subject_id"
        case predicate
        case value
        case epistemic
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case derivedFrom = "derived_from"
        case producer
        case supersededBy = "superseded_by"
    }
}
