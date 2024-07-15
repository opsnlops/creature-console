public enum CacheType: String, CustomStringConvertible, Codable {
    case animation = "animation"
    case creature = "creature"
    case playlist = "playlist"
    case unknown = "unknown"

    public var description: String {
        return self.rawValue
    }
}

public class CacheInvalidation: Hashable, Equatable, Codable, Identifiable {
    public var cacheType: CacheType

    public init() {
        self.cacheType = .unknown
    }

    public init(cacheType: CacheType) {
        self.cacheType = cacheType
    }

    public static func == (lhs: CacheInvalidation, rhs: CacheInvalidation) -> Bool {
        lhs.cacheType == rhs.cacheType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cacheType)
    }

    enum CodingKeys: String, CodingKey {
        case cacheType = "cache_type"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cacheType = try container.decode(CacheType.self, forKey: .cacheType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cacheType, forKey: .cacheType)
    }
}

extension CacheInvalidation {
    public static func mock() -> CacheInvalidation {
        return CacheInvalidation(cacheType: .unknown)
    }
}
