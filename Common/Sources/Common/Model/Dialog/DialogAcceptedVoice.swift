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
/// Whether an accepted voice still matches the script's current turns.
public enum DialogVoiceFreshness: Sendable, Equatable {
    /// The accepted take was made from exactly these turns.
    case fresh
    /// The turns changed since acceptance; the take is of text that no longer exists.
    case stale
    /// The current turns' cache key isn't known (nothing is cached for them), so the console
    /// can't say. The server will refuse a stale take itself.
    case unknown

    /// Whether the console should let a render or composition go ahead.
    public var mayProceed: Bool { self != .stale }
}

public struct DialogAcceptedVoice: Codable, Equatable, Hashable, Sendable {
    public let generationId: DialogGenerationIdentifier
    /// sha256 (64 lowercase hex chars) of the turns content this take was accepted against.
    public let dialogCacheKey: String
    /// Wall-clock milliseconds since epoch, server-stamped at acceptance.
    public let acceptedAt: Int64
    /// The promoted sound file in the permanent store. Takes live as ad-hoc sounds (24 h TTL);
    /// accepting *moves* the audio here, and un-accepting moves it back — so this file is how the
    /// accepted voice stays auditionable after the preview cache and the ad-hoc copy expire.
    public let soundFile: String?

    enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case dialogCacheKey = "dialog_cache_key"
        case acceptedAt = "accepted_at"
        case soundFile = "sound_file"
    }

    public init(
        generationId: DialogGenerationIdentifier, dialogCacheKey: String, acceptedAt: Int64,
        soundFile: String? = nil
    ) {
        self.generationId = generationId
        self.dialogCacheKey = dialogCacheKey
        self.acceptedAt = acceptedAt
        self.soundFile = soundFile
    }

    public var acceptedAtDate: Date {
        Date(timeIntervalSince1970: Double(acceptedAt) / 1_000)
    }

    /// Whether this acceptance still matches the given turns cache key. A mismatch means the
    /// turns changed since acceptance — the take is of text that no longer exists. Prefer
    /// `freshness(forCacheKey:)`: this reads "no key" as stale, which is the wrong verdict
    /// when the key simply couldn't be learned.
    public func isFresh(forCacheKey cacheKey: String?) -> Bool {
        freshness(forCacheKey: cacheKey) == .fresh
    }

    /// The acceptance against the current turns. The current key comes from the takes
    /// lookup; when nothing is cached for these turns the console has no key at all, and that
    /// is `unknown` — never `stale`. The server checks the real thing on every render and
    /// composition, so unknown may proceed and stale may not.
    public func freshness(forCacheKey cacheKey: String?) -> DialogVoiceFreshness {
        guard let cacheKey, !cacheKey.isEmpty else { return .unknown }
        return cacheKey.lowercased() == dialogCacheKey.lowercased() ? .fresh : .stale
    }
}
