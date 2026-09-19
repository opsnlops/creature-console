import Foundation

public enum DialogMusicGenerationMode: String, Codable, CaseIterable, Sendable {
    case track
    case loop
    case ambience
}

/// Which request shape a take was made with.
public enum DialogMusicRequestKind: String, Codable, Sendable {
    case prompt
    case compositionPlan = "composition_plan"
}

/// A finetune to compose with, and how strongly (0–2, default 1).
public struct MusicFinetuneSelection: Equatable, Hashable, Sendable {
    public var finetuneId: String
    public var strength: Double

    public init(finetuneId: String, strength: Double = 1.0) {
        self.finetuneId = finetuneId
        self.strength = strength
    }
}

/// `POST /api/v1/animation/dialog/music` (server #200). Exactly one composition shape is sent,
/// and only the keys that shape allows: the server rejects `seed` beside a prompt and the
/// prompt-only knobs beside a plan.
public struct DialogMusicRequest: Encodable, Equatable, Sendable {
    /// The original contract: describe the piece and let the server size it to the take.
    public struct Prompt: Equatable, Sendable {
        public var prompt: String
        public var durationExtensionMilliseconds: Int64
        public var generationMode: DialogMusicGenerationMode
        /// `false` lets the birds sing.
        public var forceInstrumental: Bool

        public init(
            prompt: String,
            durationExtensionMilliseconds: Int64 = 0,
            generationMode: DialogMusicGenerationMode = .track,
            forceInstrumental: Bool = true
        ) {
            self.prompt = prompt
            self.durationExtensionMilliseconds = durationExtensionMilliseconds
            self.generationMode = generationMode
            self.forceInstrumental = forceInstrumental
        }
    }

    public enum Composition: Equatable, Sendable {
        case prompt(Prompt)
        /// The console owns the timeline. `seed` keeps tweaks consistent between takes.
        case plan(MusicCompositionPlan, seed: Int64?)
    }

    public let scriptId: DialogScriptIdentifier
    public let dialogCacheKey: String
    public let dialogGenerationId: DialogGenerationIdentifier
    public let composition: Composition
    public let modelId: DialogMusicModel
    public let finetune: MusicFinetuneSelection?
    /// Whether ElevenLabs keeps the take so a later request can reference it. Default true:
    /// every take is a valid starting point for the next one.
    public let storeForInpainting: Bool

    enum CodingKeys: String, CodingKey {
        case scriptId = "script_id"
        case dialogCacheKey = "dialog_cache_key"
        case dialogGenerationId = "dialog_generation_id"
        case prompt
        case durationExtensionMilliseconds = "duration_extension_ms"
        case generationMode = "generation_mode"
        case forceInstrumental = "force_instrumental"
        case compositionPlan = "composition_plan"
        case seed
        case modelId = "model_id"
        case finetuneId = "finetune_id"
        case finetuneStrength = "finetune_strength"
        case storeForInpainting = "store_for_inpainting"
    }

    public init(
        scriptId: DialogScriptIdentifier,
        dialogCacheKey: String,
        dialogGenerationId: DialogGenerationIdentifier,
        composition: Composition,
        modelId: DialogMusicModel = .default,
        finetune: MusicFinetuneSelection? = nil,
        storeForInpainting: Bool = true
    ) {
        self.scriptId = scriptId
        self.dialogCacheKey = dialogCacheKey
        self.dialogGenerationId = dialogGenerationId
        self.composition = composition
        self.modelId = modelId
        self.finetune = finetune
        self.storeForInpainting = storeForInpainting
    }

    /// Prompt-mode convenience, the shape every pre-#200 caller used.
    public init(
        scriptId: DialogScriptIdentifier,
        dialogCacheKey: String,
        dialogGenerationId: DialogGenerationIdentifier,
        prompt: String,
        durationExtensionMilliseconds: Int64 = 0,
        generationMode: DialogMusicGenerationMode = .track,
        forceInstrumental: Bool = true,
        modelId: DialogMusicModel = .default,
        finetune: MusicFinetuneSelection? = nil,
        storeForInpainting: Bool = true
    ) {
        self.init(
            scriptId: scriptId,
            dialogCacheKey: dialogCacheKey,
            dialogGenerationId: dialogGenerationId,
            composition: .prompt(
                Prompt(
                    prompt: prompt,
                    durationExtensionMilliseconds: durationExtensionMilliseconds,
                    generationMode: generationMode,
                    forceInstrumental: forceInstrumental)),
            modelId: modelId,
            finetune: finetune,
            storeForInpainting: storeForInpainting)
    }

    public var prompt: String? {
        if case .prompt(let prompt) = composition { return prompt.prompt }
        return nil
    }

    public var durationExtensionMilliseconds: Int64? {
        if case .prompt(let prompt) = composition { return prompt.durationExtensionMilliseconds }
        return nil
    }

    public var generationMode: DialogMusicGenerationMode? {
        if case .prompt(let prompt) = composition { return prompt.generationMode }
        return nil
    }

    public var compositionPlan: MusicCompositionPlan? {
        if case .plan(let plan, _) = composition { return plan }
        return nil
    }

    public var seed: Int64? {
        if case .plan(_, let seed) = composition { return seed }
        return nil
    }

    public var requestKind: DialogMusicRequestKind {
        switch composition {
        case .prompt: .prompt
        case .plan: .compositionPlan
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scriptId.uuidString.lowercased(), forKey: .scriptId)
        try container.encode(dialogCacheKey, forKey: .dialogCacheKey)
        try container.encode(
            dialogGenerationId.uuidString.lowercased(), forKey: .dialogGenerationId)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(storeForInpainting, forKey: .storeForInpainting)
        if let finetune {
            try container.encode(finetune.finetuneId, forKey: .finetuneId)
            try container.encode(finetune.strength, forKey: .finetuneStrength)
        }
        switch composition {
        case .prompt(let prompt):
            try container.encode(prompt.prompt, forKey: .prompt)
            try container.encode(
                prompt.durationExtensionMilliseconds, forKey: .durationExtensionMilliseconds)
            try container.encode(prompt.generationMode, forKey: .generationMode)
            try container.encode(prompt.forceInstrumental, forKey: .forceInstrumental)
        case .plan(let plan, let seed):
            try container.encode(plan, forKey: .compositionPlan)
            try container.encodeIfPresent(seed, forKey: .seed)
        }
    }
}

/// The knobs a take was made with, echoed back in the job result and by
/// `GET …/music/generated/{id}/recipe`. `songId` + `compositionPlan` are what the next request
/// feeds on (audio reference, conditioning, edit-a-section).
public struct DialogMusicRecipe: Codable, Equatable, Sendable {
    public let modelId: String
    public let songId: String
    public let requestKind: DialogMusicRequestKind
    /// Absent for plan-mode takes.
    public let prompt: String?
    public let generationMode: DialogMusicGenerationMode?
    public let forceInstrumental: Bool?
    public let seed: Int64?
    public let finetuneId: String?
    public let finetuneStrength: Double?
    public let storedForInpainting: Bool
    /// The plan ElevenLabs actually used — present for prompt-mode takes too. Nil when the
    /// server has none to report (it sends an empty object).
    public let compositionPlan: MusicCompositionPlan?
    /// ElevenLabs' description of the song (title, genres, …), kept verbatim.
    public let songMetadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case songId = "song_id"
        case requestKind = "request_kind"
        case prompt
        case generationMode = "generation_mode"
        case forceInstrumental = "force_instrumental"
        case seed
        case finetuneId = "finetune_id"
        case finetuneStrength = "finetune_strength"
        case storedForInpainting = "stored_for_inpainting"
        case compositionPlan = "composition_plan"
        case songMetadata = "song_metadata"
    }

    private enum PlanKeys: String, CodingKey {
        case chunks
    }

    public init(
        modelId: String,
        songId: String,
        requestKind: DialogMusicRequestKind,
        prompt: String? = nil,
        generationMode: DialogMusicGenerationMode? = nil,
        forceInstrumental: Bool? = nil,
        seed: Int64? = nil,
        finetuneId: String? = nil,
        finetuneStrength: Double? = nil,
        storedForInpainting: Bool = true,
        compositionPlan: MusicCompositionPlan? = nil,
        songMetadata: [String: JSONValue] = [:]
    ) {
        self.modelId = modelId
        self.songId = songId
        self.requestKind = requestKind
        self.prompt = prompt
        self.generationMode = generationMode
        self.forceInstrumental = forceInstrumental
        self.seed = seed
        self.finetuneId = finetuneId
        self.finetuneStrength = finetuneStrength
        self.storedForInpainting = storedForInpainting
        self.compositionPlan = compositionPlan
        self.songMetadata = songMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try container.decode(String.self, forKey: .modelId)
        songId = try container.decode(String.self, forKey: .songId)
        requestKind = try container.decode(DialogMusicRequestKind.self, forKey: .requestKind)
        let rawPrompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        prompt = (rawPrompt?.isEmpty ?? true) ? nil : rawPrompt
        generationMode = try container.decodeIfPresent(
            DialogMusicGenerationMode.self, forKey: .generationMode)
        forceInstrumental = try container.decodeIfPresent(Bool.self, forKey: .forceInstrumental)
        seed = try container.decodeIfPresent(Int64.self, forKey: .seed)
        finetuneId = try container.decodeIfPresent(String.self, forKey: .finetuneId)
        finetuneStrength = try container.decodeIfPresent(Double.self, forKey: .finetuneStrength)
        storedForInpainting =
            try container.decodeIfPresent(Bool.self, forKey: .storedForInpainting) ?? false
        // `{}` means "no plan recorded"; anything with `chunks` must decode strictly.
        if container.contains(.compositionPlan),
            let probe = try? container.nestedContainer(
                keyedBy: PlanKeys.self, forKey: .compositionPlan),
            probe.contains(.chunks)
        {
            compositionPlan = try container.decode(
                MusicCompositionPlan.self, forKey: .compositionPlan)
        } else {
            compositionPlan = nil
        }
        songMetadata =
            try container.decodeIfPresent([String: JSONValue].self, forKey: .songMetadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(songId, forKey: .songId)
        try container.encode(requestKind, forKey: .requestKind)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(generationMode, forKey: .generationMode)
        try container.encodeIfPresent(forceInstrumental, forKey: .forceInstrumental)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encodeIfPresent(finetuneId, forKey: .finetuneId)
        try container.encodeIfPresent(finetuneStrength, forKey: .finetuneStrength)
        try container.encode(storedForInpainting, forKey: .storedForInpainting)
        if let compositionPlan {
            try container.encode(compositionPlan, forKey: .compositionPlan)
        } else {
            try container.encode([String: JSONValue](), forKey: .compositionPlan)
        }
        try container.encode(songMetadata, forKey: .songMetadata)
    }

    public var model: DialogMusicModel? { DialogMusicModel(rawValue: modelId) }

    public var finetune: MusicFinetuneSelection? {
        finetuneId.map { MusicFinetuneSelection(finetuneId: $0, strength: finetuneStrength ?? 1.0) }
    }

    /// Whether a later request may reference this take's audio.
    public var canBeReferenced: Bool { storedForInpainting && !songId.isEmpty }

    public var songTitle: String? {
        if case .string(let title) = songMetadata["title"], !title.isEmpty { return title }
        return nil
    }

    public var songDescription: String? {
        if case .string(let text) = songMetadata["description"], !text.isEmpty { return text }
        return nil
    }

    public var genres: [String] {
        guard case .array(let values) = songMetadata["genres"] else { return [] }
        return values.compactMap {
            if case .string(let genre) = $0 { return genre }
            return nil
        }
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
    /// Nil against a pre-3.47 server, which sends only the seven keys above.
    public let recipe: DialogMusicRecipe?

    enum CodingKeys: String, CodingKey {
        case musicGenerationId = "music_generation_id"
        case mp3Url = "mp3_url"
        case durationSeconds = "duration_seconds"
        case dialogDurationMilliseconds = "dialog_duration_ms"
        case durationExtensionMilliseconds = "duration_extension_ms"
        case requestedMusicLengthMilliseconds = "requested_music_length_ms"
        case prompt
        case modelId = "model_id"
    }

    public init(
        musicGenerationId: UUID, mp3Url: String, durationSeconds: Double,
        dialogDurationMilliseconds: Int64, durationExtensionMilliseconds: Int64,
        requestedMusicLengthMilliseconds: Int64, prompt: String,
        recipe: DialogMusicRecipe? = nil
    ) {
        self.musicGenerationId = musicGenerationId
        self.mp3Url = mp3Url
        self.durationSeconds = durationSeconds
        self.dialogDurationMilliseconds = dialogDurationMilliseconds
        self.durationExtensionMilliseconds = durationExtensionMilliseconds
        self.requestedMusicLengthMilliseconds = requestedMusicLengthMilliseconds
        self.prompt = prompt
        self.recipe = recipe
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        musicGenerationId = try container.decode(UUID.self, forKey: .musicGenerationId)
        mp3Url = try container.decode(String.self, forKey: .mp3Url)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        dialogDurationMilliseconds = try container.decode(
            Int64.self, forKey: .dialogDurationMilliseconds)
        durationExtensionMilliseconds = try container.decode(
            Int64.self, forKey: .durationExtensionMilliseconds)
        requestedMusicLengthMilliseconds = try container.decode(
            Int64.self, forKey: .requestedMusicLengthMilliseconds)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        // The recipe keys sit beside the legacy seven. Their presence is decided by one
        // required key so a 3.47 payload that fails to decode is an error, never a silent nil.
        recipe = container.contains(.modelId) ? try DialogMusicRecipe(from: decoder) : nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(musicGenerationId, forKey: .musicGenerationId)
        try container.encode(mp3Url, forKey: .mp3Url)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(dialogDurationMilliseconds, forKey: .dialogDurationMilliseconds)
        try container.encode(
            durationExtensionMilliseconds, forKey: .durationExtensionMilliseconds)
        try container.encode(
            requestedMusicLengthMilliseconds, forKey: .requestedMusicLengthMilliseconds)
        try container.encode(prompt, forKey: .prompt)
        try recipe?.encode(to: encoder)
    }

    public var finalShowDurationSeconds: Double {
        max(Double(dialogDurationMilliseconds) / 1_000, durationSeconds)
    }

    public var durationMilliseconds: Int64 { Int64((durationSeconds * 1_000).rounded()) }
}

/// `POST /api/v1/animation/dialog/music/plan`: ask the server to turn a prompt into a plan
/// sized to the accepted take, optionally starting from a prior plan.
public struct DialogMusicPlanRequest: Encodable, Equatable, Sendable {
    public let dialogCacheKey: String
    public let dialogGenerationId: DialogGenerationIdentifier
    public let prompt: String
    public let durationExtensionMilliseconds: Int64
    public let modelId: DialogMusicModel
    public let sourceCompositionPlan: MusicCompositionPlan?

    enum CodingKeys: String, CodingKey {
        case dialogCacheKey = "dialog_cache_key"
        case dialogGenerationId = "dialog_generation_id"
        case prompt
        case durationExtensionMilliseconds = "duration_extension_ms"
        case modelId = "model_id"
        case sourceCompositionPlan = "source_composition_plan"
    }

    public init(
        dialogCacheKey: String,
        dialogGenerationId: DialogGenerationIdentifier,
        prompt: String,
        durationExtensionMilliseconds: Int64 = 0,
        modelId: DialogMusicModel = .default,
        sourceCompositionPlan: MusicCompositionPlan? = nil
    ) {
        self.dialogCacheKey = dialogCacheKey
        self.dialogGenerationId = dialogGenerationId
        self.prompt = prompt
        self.durationExtensionMilliseconds = durationExtensionMilliseconds
        self.modelId = modelId
        self.sourceCompositionPlan = sourceCompositionPlan
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dialogCacheKey, forKey: .dialogCacheKey)
        try container.encode(
            dialogGenerationId.uuidString.lowercased(), forKey: .dialogGenerationId)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(durationExtensionMilliseconds, forKey: .durationExtensionMilliseconds)
        try container.encode(modelId, forKey: .modelId)
        try container.encodeIfPresent(sourceCompositionPlan, forKey: .sourceCompositionPlan)
    }
}

public struct DialogMusicPlanResult: Codable, Equatable, Sendable {
    public let modelId: String
    public let musicLengthMilliseconds: Int64
    public let dialogDurationMilliseconds: Int64
    public let durationExtensionMilliseconds: Int64
    public let compositionPlan: MusicCompositionPlan

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case musicLengthMilliseconds = "music_length_ms"
        case dialogDurationMilliseconds = "dialog_duration_ms"
        case durationExtensionMilliseconds = "duration_extension_ms"
        case compositionPlan = "composition_plan"
    }

    public init(
        modelId: String, musicLengthMilliseconds: Int64, dialogDurationMilliseconds: Int64,
        durationExtensionMilliseconds: Int64, compositionPlan: MusicCompositionPlan
    ) {
        self.modelId = modelId
        self.musicLengthMilliseconds = musicLengthMilliseconds
        self.dialogDurationMilliseconds = dialogDurationMilliseconds
        self.durationExtensionMilliseconds = durationExtensionMilliseconds
        self.compositionPlan = compositionPlan
    }
}

/// One entry of `GET /api/v1/animation/dialog/music/finetunes`.
public struct MusicFinetune: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let finetuneId: String
    public let name: String
    public let modelId: String
    public let status: String
    public let visibility: String
    public let createdBy: String
    public let tags: [String]
    public let primaryGenre: String?
    public let trainingProgress: Double

    public var id: String { finetuneId }

    enum CodingKeys: String, CodingKey {
        case finetuneId = "finetune_id"
        case name
        case modelId = "model_id"
        case status
        case visibility
        case createdBy = "created_by"
        case tags
        case primaryGenre = "primary_genre"
        case trainingProgress = "training_progress"
    }

    public init(
        finetuneId: String, name: String, modelId: String, status: String, visibility: String,
        createdBy: String, tags: [String], primaryGenre: String? = nil,
        trainingProgress: Double
    ) {
        self.finetuneId = finetuneId
        self.name = name
        self.modelId = modelId
        self.status = status
        self.visibility = visibility
        self.createdBy = createdBy
        self.tags = tags
        self.primaryGenre = primaryGenre
        self.trainingProgress = trainingProgress
    }

    public var model: DialogMusicModel? { DialogMusicModel(rawValue: modelId) }
    public var isReady: Bool { status == "completed" }
}

public struct MusicFinetuneList: Codable, Equatable, Sendable {
    public let count: Int
    public let items: [MusicFinetune]

    public init(count: Int, items: [MusicFinetune]) {
        self.count = count
        self.items = items
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
    /// Empty for plan-mode takes; the recipe endpoint has the plan.
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
