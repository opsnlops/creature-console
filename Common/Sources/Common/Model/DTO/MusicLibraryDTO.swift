import Foundation

// The music library (creature-server #202): dialog-free generation, saved pieces with
// versions, and server-side refinement. Every request mirrors `src/api/MusicContracts.h`,
// which rejects unknown fields and cross-mode fields with a full field path.

/// `POST /api/v1/music/generate` → 202 job of type `music`. Exactly one mode.
public struct MusicGenerateRequest: Encodable, Equatable, Sendable {
    public enum Composition: Equatable, Sendable {
        /// Describe it; the length is explicit because there is no dialog to size it to.
        case prompt(DialogMusicRequest.Prompt, musicLengthMilliseconds: Int64)
        /// The console owns the timeline, as in #200.
        case plan(MusicCompositionPlan, seed: Int64?)
        /// The refinement builder: the full editable plan for the new version. Sections in
        /// `keep` must be unchanged from the base version's section at the same index (text,
        /// styles, adherence and duration) and become audio references; everything else is
        /// composed, conditioned on the base's span at that index when there is one.
        case sections(
            [MusicGenerationChunk], baseVersionId: UUID?, keep: [Int],
            conditionStrength: MusicConditionStrength?, seed: Int64?)
    }

    public let composition: Composition
    /// The piece this candidate refines; required when `baseVersionId` is set.
    public let pieceId: UUID?
    public let modelId: DialogMusicModel
    public let finetune: MusicFinetuneSelection?
    public let storeForInpainting: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case musicLengthMilliseconds = "music_length_ms"
        case generationMode = "generation_mode"
        case forceInstrumental = "force_instrumental"
        case compositionPlan = "composition_plan"
        case seed
        case sections
        case baseVersionId = "base_version_id"
        case keep
        case conditionStrength = "condition_strength"
        case pieceId = "piece_id"
        case modelId = "model_id"
        case finetuneId = "finetune_id"
        case finetuneStrength = "finetune_strength"
        case storeForInpainting = "store_for_inpainting"
    }

    public init(
        composition: Composition,
        pieceId: UUID? = nil,
        modelId: DialogMusicModel = .default,
        finetune: MusicFinetuneSelection? = nil,
        storeForInpainting: Bool = true
    ) {
        self.composition = composition
        self.pieceId = pieceId
        self.modelId = modelId
        self.finetune = finetune
        self.storeForInpainting = storeForInpainting
    }

    public var requestKind: DialogMusicRequestKind {
        switch composition {
        case .prompt: .prompt
        case .plan: .compositionPlan
        case .sections: .sections
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(storeForInpainting, forKey: .storeForInpainting)
        if let finetune {
            try container.encode(finetune.finetuneId, forKey: .finetuneId)
            try container.encode(finetune.strength, forKey: .finetuneStrength)
        }
        try container.encodeIfPresent(pieceId?.uuidString.lowercased(), forKey: .pieceId)
        switch composition {
        case .prompt(let prompt, let length):
            try container.encode(prompt.prompt, forKey: .prompt)
            try container.encode(length, forKey: .musicLengthMilliseconds)
            try container.encode(prompt.generationMode, forKey: .generationMode)
            try container.encode(prompt.forceInstrumental, forKey: .forceInstrumental)
        case .plan(let plan, let seed):
            try container.encode(plan, forKey: .compositionPlan)
            try container.encodeIfPresent(seed, forKey: .seed)
        case .sections(let sections, let baseVersionId, let keep, let strength, let seed):
            try container.encode(sections.map { $0.unconditioned() }, forKey: .sections)
            try container.encodeIfPresent(
                baseVersionId?.uuidString.lowercased(), forKey: .baseVersionId)
            if !keep.isEmpty {
                try container.encode(keep, forKey: .keep)
            }
            try container.encodeIfPresent(strength, forKey: .conditionStrength)
            try container.encodeIfPresent(seed, forKey: .seed)
        }
    }
}

/// `POST /api/v1/music/generated/{id}/save`: a candidate becomes a new piece (`title`) or a new
/// version of `pieceId`. `sections` are only needed for a candidate that doesn't carry them.
public struct MusicSaveRequest: Encodable, Equatable, Sendable {
    public let title: String?
    public let notes: String?
    public let pieceId: UUID?
    public let sections: [MusicGenerationChunk]?

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case pieceId = "piece_id"
        case sections
    }

    public init(
        title: String? = nil, notes: String? = nil, pieceId: UUID? = nil,
        sections: [MusicGenerationChunk]? = nil
    ) {
        self.title = title
        self.notes = notes
        self.pieceId = pieceId
        self.sections = sections
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(pieceId?.uuidString.lowercased(), forKey: .pieceId)
        try container.encodeIfPresent(sections?.map { $0.unconditioned() }, forKey: .sections)
    }
}

/// `PUT /api/v1/music/{id}`.
public struct MusicPieceUpdateRequest: Encodable, Equatable, Sendable {
    public let title: String?
    public let notes: String?
    public let currentVersionId: UUID?

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case currentVersionId = "current_version_id"
    }

    public init(title: String? = nil, notes: String? = nil, currentVersionId: UUID? = nil) {
        self.title = title
        self.notes = notes
        self.currentVersionId = currentVersionId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(
            currentVersionId?.uuidString.lowercased(), forKey: .currentVersionId)
    }
}

/// `POST /api/v1/music/{id}/refine`: the instruction box. Synchronous, no audio.
public struct MusicRefineRequest: Encodable, Equatable, Sendable {
    public let instruction: String
    /// The version to start from; the piece's current version when nil.
    public let versionId: UUID?

    enum CodingKeys: String, CodingKey {
        case instruction
        case versionId = "version_id"
    }

    public init(instruction: String, versionId: UUID? = nil) {
        self.instruction = instruction
        self.versionId = versionId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(instruction, forKey: .instruction)
        try container.encodeIfPresent(versionId?.uuidString.lowercased(), forKey: .versionId)
    }
}

/// A proposed set of sections and which of them differ from the base version, by index.
public struct MusicRefineResult: Decodable, Equatable, Sendable {
    public let baseVersionId: UUID
    public let modelId: String
    public let musicLengthMilliseconds: Int64
    public let sections: [MusicGenerationChunk]
    public let changed: [Int]
    public let kept: [Int]

    enum CodingKeys: String, CodingKey {
        case baseVersionId = "base_version_id"
        case modelId = "model_id"
        case musicLengthMilliseconds = "music_length_ms"
        case sections
        case changed
        case kept
    }

    public init(
        baseVersionId: UUID, modelId: String, musicLengthMilliseconds: Int64,
        sections: [MusicGenerationChunk], changed: [Int], kept: [Int]
    ) {
        self.baseVersionId = baseVersionId
        self.modelId = modelId
        self.musicLengthMilliseconds = musicLengthMilliseconds
        self.sections = sections
        self.changed = changed
        self.kept = kept
    }
}

/// `POST /api/v1/music/plan`: sections for a brand-new piece, from a description and a length.
public struct MusicPlanRequest: Encodable, Equatable, Sendable {
    public let prompt: String
    public let musicLengthMilliseconds: Int64
    public let modelId: DialogMusicModel
    public let sourceSections: [MusicGenerationChunk]?

    enum CodingKeys: String, CodingKey {
        case prompt
        case musicLengthMilliseconds = "music_length_ms"
        case modelId = "model_id"
        case sourceSections = "source_sections"
    }

    public init(
        prompt: String, musicLengthMilliseconds: Int64, modelId: DialogMusicModel = .default,
        sourceSections: [MusicGenerationChunk]? = nil
    ) {
        self.prompt = prompt
        self.musicLengthMilliseconds = musicLengthMilliseconds
        self.modelId = modelId
        self.sourceSections = sourceSections
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(musicLengthMilliseconds, forKey: .musicLengthMilliseconds)
        try container.encode(modelId, forKey: .modelId)
        try container.encodeIfPresent(
            sourceSections?.map { $0.unconditioned() }, forKey: .sourceSections)
    }
}

public struct MusicPlanResult: Decodable, Equatable, Sendable {
    public let modelId: String
    public let musicLengthMilliseconds: Int64
    public let sections: [MusicGenerationChunk]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case musicLengthMilliseconds = "music_length_ms"
        case sections
    }

    public init(modelId: String, musicLengthMilliseconds: Int64, sections: [MusicGenerationChunk]) {
        self.modelId = modelId
        self.musicLengthMilliseconds = musicLengthMilliseconds
        self.sections = sections
    }
}

/// The dialog a library version was composed against, when it came from the dialog editor.
public struct SavedMusicSourceDialog: Codable, Equatable, Hashable, Sendable {
    public let scriptId: DialogScriptIdentifier
    public let dialogCacheKey: String
    public let dialogGenerationId: DialogGenerationIdentifier

    enum CodingKeys: String, CodingKey {
        case scriptId = "script_id"
        case dialogCacheKey = "dialog_cache_key"
        case dialogGenerationId = "dialog_generation_id"
    }

    public init(
        scriptId: DialogScriptIdentifier, dialogCacheKey: String,
        dialogGenerationId: DialogGenerationIdentifier
    ) {
        self.scriptId = scriptId
        self.dialogCacheKey = dialogCacheKey
        self.dialogGenerationId = dialogGenerationId
    }
}

/// One version of a saved piece: one generation, with the editable sections it was made
/// from, the song the next refinement references, and its permanent audio.
public struct SavedMusicVersion: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let songId: String
    public let soundFile: String
    public let mp3Url: String
    public let durationMilliseconds: Int64
    public let recipe: DialogMusicRecipe?
    public let sections: [MusicGenerationChunk]
    public let baseVersionId: UUID?
    public let sourceDialog: SavedMusicSourceDialog?
    public let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case soundFile = "sound_file"
        case mp3Url = "mp3_url"
        case durationMilliseconds = "duration_ms"
        case recipe
        case sections
        case baseVersionId = "base_version_id"
        case sourceDialog = "source_dialog"
        case createdAt = "created_at"
    }

    public init(
        id: UUID, songId: String, soundFile: String, mp3Url: String,
        durationMilliseconds: Int64, recipe: DialogMusicRecipe? = nil,
        sections: [MusicGenerationChunk], baseVersionId: UUID? = nil,
        sourceDialog: SavedMusicSourceDialog? = nil, createdAt: Int64
    ) {
        self.id = id
        self.songId = songId
        self.soundFile = soundFile
        self.mp3Url = mp3Url
        self.durationMilliseconds = durationMilliseconds
        self.recipe = recipe
        self.sections = sections
        self.baseVersionId = baseVersionId
        self.sourceDialog = sourceDialog
        self.createdAt = createdAt
    }

    private enum RecipeProbeKeys: String, CodingKey {
        case modelId = "model_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        songId = try container.decode(String.self, forKey: .songId)
        soundFile = try container.decode(String.self, forKey: .soundFile)
        mp3Url = try container.decode(String.self, forKey: .mp3Url)
        durationMilliseconds = try container.decode(Int64.self, forKey: .durationMilliseconds)
        // The server sends `{}` when a version's provenance carried no recipe.
        if let probe = try? container.nestedContainer(
            keyedBy: RecipeProbeKeys.self, forKey: .recipe),
            probe.contains(.modelId)
        {
            recipe = try container.decode(DialogMusicRecipe.self, forKey: .recipe)
        } else {
            recipe = nil
        }
        sections =
            try container.decodeIfPresent([MusicGenerationChunk].self, forKey: .sections) ?? []
        baseVersionId = try container.decodeIfPresent(UUID.self, forKey: .baseVersionId)
        sourceDialog = try container.decodeIfPresent(
            SavedMusicSourceDialog.self, forKey: .sourceDialog)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(songId, forKey: .songId)
        try container.encode(soundFile, forKey: .soundFile)
        try container.encode(mp3Url, forKey: .mp3Url)
        try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
        if let recipe {
            try container.encode(recipe, forKey: .recipe)
        } else {
            try container.encode([String: JSONValue](), forKey: .recipe)
        }
        try container.encode(sections, forKey: .sections)
        try container.encodeIfPresent(baseVersionId, forKey: .baseVersionId)
        try container.encodeIfPresent(sourceDialog, forKey: .sourceDialog)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public var createdAtDate: Date { Date(timeIntervalSince1970: Double(createdAt) / 1_000) }

    /// Whether the next refinement can reference this version's audio.
    public var canBeReferenced: Bool { !songId.isEmpty }
}

/// A saved piece: a title, notes and an append-only list of versions. `currentVersionId` is
/// the one that plays and that refinements start from.
public struct SavedMusicPiece: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var currentVersionId: UUID?
    public var versions: [SavedMusicVersion]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case currentVersionId = "current_version_id"
        case versions
    }

    public init(
        id: UUID, title: String, notes: String = "", createdAt: Int64, updatedAt: Int64,
        currentVersionId: UUID?, versions: [SavedMusicVersion]
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentVersionId = currentVersionId
        self.versions = versions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        let current = try container.decodeIfPresent(String.self, forKey: .currentVersionId)
        currentVersionId = current.flatMap { $0.isEmpty ? nil : UUID(uuidString: $0) }
        versions = try container.decodeIfPresent([SavedMusicVersion].self, forKey: .versions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(
            currentVersionId?.uuidString.lowercased() ?? "", forKey: .currentVersionId)
        try container.encode(versions, forKey: .versions)
    }

    /// The version that plays and that refinements start from; the newest when the pointer
    /// is missing or dangling.
    public var currentVersion: SavedMusicVersion? {
        if let currentVersionId, let current = versions.first(where: { $0.id == currentVersionId })
        {
            return current
        }
        return versions.max { $0.createdAt < $1.createdAt }
    }

    public func version(withId id: UUID) -> SavedMusicVersion? {
        versions.first { $0.id == id }
    }

    public var createdAtDate: Date { Date(timeIntervalSince1970: Double(createdAt) / 1_000) }
    public var updatedAtDate: Date { Date(timeIntervalSince1970: Double(updatedAt) / 1_000) }
}

/// Response body for `GET /api/v1/music`.
public struct SavedMusicPieceListDTO: Codable, Sendable {
    public var count: Int32
    public var items: [SavedMusicPiece]

    public init(count: Int32, items: [SavedMusicPiece]) {
        self.count = count
        self.items = items
    }
}
