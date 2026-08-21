public enum CacheType: String, CustomStringConvertible, Codable, Sendable {
    case animation = "animation"
    case creature = "creature"
    case playlist = "playlist"
    case soundList = "sound-list"
    case adHocAnimationList = "ad-hoc-animation-list"
    case adHocSoundList = "ad-hoc-sound-list"
    case fixture = "fixture"
    case dialogScriptList = "dialog-script-list"
    case storyboardList = "storyboard-list"
    case stageList = "stage-list"
    case adHocExchangeList = "ad-hoc-exchange-list"
    case unknown = "unknown"

    public var description: String {
        return self.rawValue
    }

    /// The server adds cache types over time; a value this build doesn't know
    /// collapses to `.unknown` instead of failing the whole invalidation message.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CacheType(rawValue: value) ?? .unknown
    }
}

public struct CacheInvalidation: Hashable, Codable, Sendable {
    public let cacheType: CacheType

    public init() {
        self.cacheType = .unknown
    }

    public init(cacheType: CacheType) {
        self.cacheType = cacheType
    }

    enum CodingKeys: String, CodingKey {
        case cacheType = "cache_type"
    }
}

extension CacheInvalidation {
    public static func mock() -> CacheInvalidation {
        return CacheInvalidation(cacheType: .unknown)
    }
}
