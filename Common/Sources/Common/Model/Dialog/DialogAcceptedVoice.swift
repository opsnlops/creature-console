import Foundation

/// The voice take a dialog script has explicitly accepted — the sibling of
/// ``DialogBackgroundMusic``, and the only voice a render is allowed to use.
///
/// Takes are audition *candidates* until one is accepted; acceptance writes this onto the script
/// (server issue #131), where it survives preview-cache expiry, app restarts, and device changes.
/// Renders are blocked without a **fresh** acceptance: nothing plays on the birds that nobody
/// listened to.
///
/// `dialogCacheKey` is the staleness test. It's the sha256 of the turns the take was accepted
/// against; when the script's current turns hash differently, the acceptance is *stale* — kept
/// and reported, never silently cleared. The audio is of the old text, so a stale acceptance
/// can't render; re-audition and re-accept is the fix.
public struct DialogAcceptedVoice: Codable, Equatable, Hashable, Sendable {
    public let generationId: DialogGenerationIdentifier
    /// sha256 (64 lowercase hex chars) of the turns content this take was accepted against.
    public let dialogCacheKey: String
    /// Wall-clock milliseconds since epoch, server-stamped at acceptance.
    public let acceptedAt: Int64

    enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case dialogCacheKey = "dialog_cache_key"
        case acceptedAt = "accepted_at"
    }

    public init(
        generationId: DialogGenerationIdentifier, dialogCacheKey: String, acceptedAt: Int64
    ) {
        self.generationId = generationId
        self.dialogCacheKey = dialogCacheKey
        self.acceptedAt = acceptedAt
    }

    public var acceptedAtDate: Date {
        Date(timeIntervalSince1970: Double(acceptedAt) / 1_000)
    }

    /// Whether this acceptance still matches the given turns cache key. A mismatch means the
    /// turns changed since acceptance — the take is of text that no longer exists.
    public func isFresh(forCacheKey cacheKey: String?) -> Bool {
        guard let cacheKey, !cacheKey.isEmpty else { return false }
        return cacheKey.lowercased() == dialogCacheKey.lowercased()
    }
}
