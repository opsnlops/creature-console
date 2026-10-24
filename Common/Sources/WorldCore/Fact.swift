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
    /// Who said it: the source of the event the fact came from - `mind:beaky` for what a bird
    /// kept, `bridge:contacts` for the address book, `librarian:beaky` for a fact she filed.
    /// The producer is the reducer that cast it, the same for all of those; this is what the
    /// librarian needs to find "everything a mind kept" (#229). Nil on a fact from before
    /// 0.49.0 whose event has gone.
    public var origin: SourceID?
    /// The bird it was learned in a whisper with (#263): kept while that bird answered April's
    /// "@beaky …", so only that bird is handed it. Nil for anything learned in the room.
    public var aloneWith: EntityID?

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
        supersededBy: FactID? = nil,
        origin: SourceID? = nil,
        aloneWith: EntityID? = nil
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
        self.origin = origin
        self.aloneWith = aloneWith
    }

    /// Whether `characterID`'s mind may be handed this: anything learned in the room, and what
    /// was learned in a whisper with it.
    public func isHeard(by characterID: EntityID?) -> Bool {
        Whispers.isHeard(aloneWith, by: characterID)
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
        self.origin = try container.decodeIfPresent(SourceID.self, forKey: .origin)
        self.aloneWith = try container.decodeIfPresent(EntityID.self, forKey: .aloneWith)
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
        case origin
        case aloneWith = "alone_with"
    }
}
