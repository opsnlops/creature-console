import Foundation

public enum DialogMusicGenerationMode: String, Codable, CaseIterable, Sendable {
    case track
    case loop
    case ambience
}

public struct DialogMusicRequest: Encodable, Equatable, Sendable {
    public let scriptId: DialogScriptIdentifier
    public let dialogCacheKey: String
    public let dialogGenerationId: DialogGenerationIdentifier
    public let prompt: String
    public let durationExtensionMilliseconds: Int64
    public let generationMode: DialogMusicGenerationMode

    enum CodingKeys: String, CodingKey {
        case scriptId = "script_id"
        case dialogCacheKey = "dialog_cache_key"
        case dialogGenerationId = "dialog_generation_id"
        case prompt
        case durationExtensionMilliseconds = "duration_extension_ms"
        case generationMode = "generation_mode"
    }

    public init(
        scriptId: DialogScriptIdentifier,
        dialogCacheKey: String,
        dialogGenerationId: DialogGenerationIdentifier,
        prompt: String,
        durationExtensionMilliseconds: Int64 = 0,
        generationMode: DialogMusicGenerationMode = .track
    ) {
        self.scriptId = scriptId
        self.dialogCacheKey = dialogCacheKey
        self.dialogGenerationId = dialogGenerationId
        self.prompt = prompt
        self.durationExtensionMilliseconds = durationExtensionMilliseconds
        self.generationMode = generationMode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scriptId.uuidString.lowercased(), forKey: .scriptId)
        try container.encode(dialogCacheKey, forKey: .dialogCacheKey)
        try container.encode(
            dialogGenerationId.uuidString.lowercased(), forKey: .dialogGenerationId)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(durationExtensionMilliseconds, forKey: .durationExtensionMilliseconds)
        try container.encode(generationMode, forKey: .generationMode)
    }
}

public struct DialogMusicGenerationResult: Codable, Equatable, Sendable {
    public let musicGenerationId: UUID
    public let mp3Url: String
    public let durationSeconds: Double
    public let dialogDurationMilliseconds: Int64
    public let durationExtensionMilliseconds: Int64
    public let requestedMusicLengthMilliseconds: Int64
    public let prompt: String

    enum CodingKeys: String, CodingKey {
        case musicGenerationId = "music_generation_id"
        case mp3Url = "mp3_url"
        case durationSeconds = "duration_seconds"
        case dialogDurationMilliseconds = "dialog_duration_ms"
        case durationExtensionMilliseconds = "duration_extension_ms"
        case requestedMusicLengthMilliseconds = "requested_music_length_ms"
        case prompt
    }

    public init(
        musicGenerationId: UUID, mp3Url: String, durationSeconds: Double,
        dialogDurationMilliseconds: Int64, durationExtensionMilliseconds: Int64,
        requestedMusicLengthMilliseconds: Int64, prompt: String
    ) {
        self.musicGenerationId = musicGenerationId
        self.mp3Url = mp3Url
        self.durationSeconds = durationSeconds
        self.dialogDurationMilliseconds = dialogDurationMilliseconds
        self.durationExtensionMilliseconds = durationExtensionMilliseconds
        self.requestedMusicLengthMilliseconds = requestedMusicLengthMilliseconds
        self.prompt = prompt
    }

    public var finalShowDurationSeconds: Double {
        max(Double(dialogDurationMilliseconds) / 1_000, durationSeconds)
    }
}

public struct DialogMusicPromotionResult: Codable, Equatable, Sendable {
    public let musicGenerationId: UUID
    public let soundFile: String
    public let mp3Url: String

    enum CodingKeys: String, CodingKey {
        case musicGenerationId = "music_generation_id"
        case soundFile = "sound_file"
        case mp3Url = "mp3_url"
    }

    public init(musicGenerationId: UUID, soundFile: String, mp3Url: String) {
        self.musicGenerationId = musicGenerationId
        self.soundFile = soundFile
        self.mp3Url = mp3Url
    }
}

public struct DialogBackgroundMusic: Codable, Equatable, Hashable, Sendable {
    public let soundFile: String
    public let generationId: UUID
    public let prompt: String
    public let acceptedAt: Int64
    /// The voice take this music was composed against (server#136). Optional: accepted music
    /// that predates the field decodes as nil, and the client shows no verdict rather than a
    /// false one.
    public let sourceDialogGenerationId: DialogGenerationIdentifier?
    public let sourceDialogCacheKey: String?

    enum CodingKeys: String, CodingKey {
        case soundFile = "sound_file"
        case generationId = "generation_id"
        case prompt
        case acceptedAt = "accepted_at"
        case sourceDialogGenerationId = "source_dialog_generation_id"
        case sourceDialogCacheKey = "source_dialog_cache_key"
    }

    public init(
        soundFile: String, generationId: UUID, prompt: String, acceptedAt: Int64,
        sourceDialogGenerationId: DialogGenerationIdentifier? = nil,
        sourceDialogCacheKey: String? = nil
    ) {
        self.soundFile = soundFile
        self.generationId = generationId
        self.prompt = prompt
        self.acceptedAt = acceptedAt
        self.sourceDialogGenerationId = sourceDialogGenerationId
        self.sourceDialogCacheKey = sourceDialogCacheKey
    }

    /// Whether this music was composed against the given accepted voice. Nil when the server
    /// hasn't recorded provenance (pre-#136 acceptances) — unknown, not stale.
    public func matchesAcceptedVoice(_ voice: DialogAcceptedVoice?) -> Bool? {
        guard let sourceDialogGenerationId else { return nil }
        guard let voice else { return false }
        return sourceDialogGenerationId == voice.generationId
    }

    public var acceptedAtDate: Date {
        Date(timeIntervalSince1970: Double(acceptedAt) / 1_000)
    }
}
