import Foundation

public struct AdHocAnimationSummary: Codable, Equatable, Sendable, Identifiable {

    public let animationId: AnimationIdentifier
    public let metadata: AnimationMetadata
    public let createdAt: Date?

    public var id: AnimationIdentifier { animationId }

    enum CodingKeys: String, CodingKey {
        case animationId = "animation_id"
        case metadata
        case createdAt = "created_at"
    }

    public init(animationId: AnimationIdentifier, metadata: AnimationMetadata, createdAt: Date?) {
        self.animationId = animationId
        self.metadata = metadata
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)
        metadata = try container.decode(AnimationMetadata.self, forKey: .metadata)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = AdHocAnimationSummary.parse(dateString)
        } else {
            createdAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(animationId, forKey: .animationId)
        try container.encode(metadata, forKey: .metadata)
        if let createdAt {
            let dateString = AdHocAnimationSummary.format(createdAt)
            try container.encode(dateString, forKey: .createdAt)
        }
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct AdHocAnimationListDTO: Codable, Equatable, Sendable {
    public let count: UInt32
    public let items: [AdHocAnimationSummary]

    public init(count: UInt32, items: [AdHocAnimationSummary]) {
        self.count = count
        self.items = items
    }
}
