import Foundation

/// Request body for the dialog preview endpoints (`/preview/meta`, `/preview/lookup`,
/// `/preview/multichannel`).
///
/// The preview endpoints are keyed purely by the scene's **turns** (`turns` is required on the
/// wire; the cache key is `sha256(turns)`). Unlike the render endpoint, there is no
/// `script_id` — to preview a saved script, fetch it and preview its turns. `generationId`
/// requests a specific cached take and `regenerate` forces a fresh one.
public struct DialogPreviewRequest: Encodable, Sendable {

    public var turns: [DialogScriptTurn]
    public var generationId: DialogGenerationIdentifier?
    public var regenerate: Bool?

    enum CodingKeys: String, CodingKey {
        case turns
        case generationId = "generation_id"
        case regenerate
    }

    public init(
        turns: [DialogScriptTurn],
        generationId: DialogGenerationIdentifier? = nil,
        regenerate: Bool? = nil
    ) {
        self.turns = turns
        self.generationId = generationId
        self.regenerate = regenerate
    }

    public static func fromTurns(
        _ turns: [DialogScriptTurn],
        generationId: DialogGenerationIdentifier? = nil,
        regenerate: Bool? = nil
    ) -> DialogPreviewRequest {
        DialogPreviewRequest(turns: turns, generationId: generationId, regenerate: regenerate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(turns, forKey: .turns)
        try container.encodeIfPresent(
            generationId?.uuidString.lowercased(), forKey: .generationId)
        try container.encodeIfPresent(regenerate, forKey: .regenerate)
    }
}

/// Which speaker a character range of the mixdown belongs to.
public struct DialogVoiceSegment: Codable, Sendable, Equatable {
    public var voiceId: String
    public var characterStartIndex: Int
    public var characterEndIndex: Int
    public var dialogInputIndex: Int

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case characterStartIndex = "character_start_index"
        case characterEndIndex = "character_end_index"
        case dialogInputIndex = "dialog_input_index"
    }
}

/// Forced-alignment timing for a single word or character (seconds from start of audio).
public struct DialogAlignmentToken: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
}

/// Response body for `POST /api/v1/animation/dialog/preview/meta`.
///
/// `audioUrl` is a server-relative path (it already begins with `/api/v1/...`); build the
/// absolute URL with `CreatureServerClient.makeAbsoluteURL(fromRelativePath:)` before handing
/// it to the audio player. The same input + multiple `regenerate` calls share a `cacheKey`
/// but produce distinct `generationId`s.
public struct DialogPreviewMetaDTO: Decodable, Sendable, Equatable {

    public var cacheKey: String
    public var generationId: DialogGenerationIdentifier
    public var cached: Bool
    public var audioUrl: String
    public var audioFormat: String
    public var sampleRate: Int
    public var durationSeconds: Double
    public var voiceSegments: [DialogVoiceSegment]
    public var forcedAlignmentWords: [DialogAlignmentToken]
    public var forcedAlignmentChars: [DialogAlignmentToken]
    public var forcedAlignmentLoss: Double?

    enum CodingKeys: String, CodingKey {
        case cacheKey = "cache_key"
        case generationId = "generation_id"
        case cached
        case audioUrl = "audio_url"
        case audioFormat = "audio_format"
        case sampleRate = "sample_rate"
        case durationSeconds = "duration_seconds"
        case voiceSegments = "voice_segments"
        case forcedAlignmentWords = "forced_alignment_words"
        case forcedAlignmentChars = "forced_alignment_chars"
        case forcedAlignmentLoss = "forced_alignment_loss"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cacheKey = try container.decode(String.self, forKey: .cacheKey)
        generationId = try container.decode(DialogGenerationIdentifier.self, forKey: .generationId)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached) ?? false
        audioUrl = try container.decode(String.self, forKey: .audioUrl)
        audioFormat = try container.decodeIfPresent(String.self, forKey: .audioFormat) ?? ""
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 0
        durationSeconds =
            try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        voiceSegments =
            try container.decodeIfPresent([DialogVoiceSegment].self, forKey: .voiceSegments) ?? []
        forcedAlignmentWords =
            try container.decodeIfPresent(
                [DialogAlignmentToken].self, forKey: .forcedAlignmentWords) ?? []
        forcedAlignmentChars =
            try container.decodeIfPresent(
                [DialogAlignmentToken].self, forKey: .forcedAlignmentChars) ?? []
        forcedAlignmentLoss = try container.decodeIfPresent(
            Double.self, forKey: .forcedAlignmentLoss)
    }
}

/// Response body for `POST /api/v1/animation/dialog/preview/lookup` (200), or `404` when
/// nothing is cached for the supplied turns. Generations are newest-first.
public struct DialogPreviewLookupDTO: Decodable, Sendable, Equatable {

    public var cacheKey: String
    public var latestGenerationId: DialogGenerationIdentifier
    public var generations: [Generation]

    /// One cached ElevenLabs take. `createdAt` is kept as the raw ISO-8601 string because the
    /// shared POST decoder has no date strategy configured; parse via ``createdAtDate`` if needed.
    public struct Generation: Decodable, Sendable, Equatable, Identifiable {
        public var generationId: DialogGenerationIdentifier
        public var createdAt: String

        public var id: DialogGenerationIdentifier { generationId }

        enum CodingKeys: String, CodingKey {
            case generationId = "generation_id"
            case createdAt = "created_at"
        }

        public var createdAtDate: Date? {
            ISO8601DateFormatter().date(from: createdAt)
        }
    }

    enum CodingKeys: String, CodingKey {
        case cacheKey = "cache_key"
        case latestGenerationId = "latest_generation_id"
        case generations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cacheKey = try container.decode(String.self, forKey: .cacheKey)
        latestGenerationId = try container.decode(
            DialogGenerationIdentifier.self, forKey: .latestGenerationId)
        generations = try container.decodeIfPresent([Generation].self, forKey: .generations) ?? []
    }
}
