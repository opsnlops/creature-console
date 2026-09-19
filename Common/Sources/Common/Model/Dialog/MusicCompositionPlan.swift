import Foundation

/// ElevenLabs Music model the server may be asked for (server #200). `music_v1` is
/// deprecated upstream and the server rejects it.
public enum DialogMusicModel: String, Codable, CaseIterable, Sendable, Identifiable {
    case v2 = "music_v2"
    case v2_5 = "music_v2_5"

    public static let `default` = DialogMusicModel.v2_5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .v2: "Music 2"
        case .v2_5: "Music 2.5"
        }
    }
}

/// How closely a generation chunk follows the plan's surrounding context.
public enum MusicContextAdherence: String, Codable, CaseIterable, Sendable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

/// How strongly a generation chunk should "sound like" its conditioning reference.
public enum MusicConditionStrength: String, Codable, CaseIterable, Sendable, Identifiable {
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .xhigh: "Extra high"
        default: rawValue.capitalized
        }
    }
}

/// A span of a previously generated song, by ElevenLabs `song_id`. Used both as an
/// audio-reference chunk (re-render this span) and as a conditioning reference (sound like
/// this span). Wire form: `{"song_id": …, "range": {"start_ms": …, "end_ms": …}}`.
public struct MusicAudioRange: Codable, Equatable, Hashable, Sendable {
    public var songId: String
    public var startMilliseconds: Int64
    public var endMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case range
    }

    enum RangeKeys: String, CodingKey {
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
    }

    public init(songId: String, startMilliseconds: Int64, endMilliseconds: Int64) {
        self.songId = songId
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songId = try container.decode(String.self, forKey: .songId)
        let range = try container.nestedContainer(keyedBy: RangeKeys.self, forKey: .range)
        startMilliseconds = try range.decode(Int64.self, forKey: .startMilliseconds)
        endMilliseconds = try range.decode(Int64.self, forKey: .endMilliseconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(songId, forKey: .songId)
        var range = container.nestedContainer(keyedBy: RangeKeys.self, forKey: .range)
        try range.encode(startMilliseconds, forKey: .startMilliseconds)
        try range.encode(endMilliseconds, forKey: .endMilliseconds)
    }

    public var lengthMilliseconds: Int64 { endMilliseconds - startMilliseconds }
}

/// A chunk the model composes fresh. `text` may carry a `[Section]` prefix and `{direction}`
/// hints inline; leaving lyric lines out of it is what "instrumental" means in plan mode.
public struct MusicGenerationChunk: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var durationMilliseconds: Int64
    public var positiveStyles: [String]
    public var negativeStyles: [String]
    public var contextAdherence: MusicContextAdherence
    public var conditioningReference: MusicAudioRange?
    public var conditionStrength: MusicConditionStrength?

    enum CodingKeys: String, CodingKey {
        case text
        case durationMilliseconds = "duration_ms"
        case positiveStyles = "positive_styles"
        case negativeStyles = "negative_styles"
        case contextAdherence = "context_adherence"
        case conditioningReference = "conditioning_ref"
        case conditionStrength = "condition_strength"
    }

    public init(
        text: String,
        durationMilliseconds: Int64,
        positiveStyles: [String] = [],
        negativeStyles: [String] = [],
        contextAdherence: MusicContextAdherence = .high,
        conditioningReference: MusicAudioRange? = nil,
        conditionStrength: MusicConditionStrength? = nil
    ) {
        self.text = text
        self.durationMilliseconds = durationMilliseconds
        self.positiveStyles = positiveStyles
        self.negativeStyles = negativeStyles
        self.contextAdherence = contextAdherence
        self.conditioningReference = conditioningReference
        self.conditionStrength = conditionStrength
    }

    /// ElevenLabs' own drafted plans carry explicit `null` for the two conditioning fields;
    /// `decodeIfPresent` reads null as absent, which is what the server documents too.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        durationMilliseconds = try container.decode(Int64.self, forKey: .durationMilliseconds)
        positiveStyles = try container.decodeIfPresent([String].self, forKey: .positiveStyles) ?? []
        negativeStyles = try container.decodeIfPresent([String].self, forKey: .negativeStyles) ?? []
        contextAdherence =
            try container.decodeIfPresent(MusicContextAdherence.self, forKey: .contextAdherence)
            ?? .high
        conditioningReference = try container.decodeIfPresent(
            MusicAudioRange.self, forKey: .conditioningReference)
        conditionStrength = try container.decodeIfPresent(
            MusicConditionStrength.self, forKey: .conditionStrength)
    }

    /// Never emits the conditioning keys when unset: the server treats null as absent but the
    /// canonical form is to leave them out.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encode(positiveStyles, forKey: .positiveStyles)
        try container.encode(negativeStyles, forKey: .negativeStyles)
        try container.encode(contextAdherence, forKey: .contextAdherence)
        try container.encodeIfPresent(conditioningReference, forKey: .conditioningReference)
        try container.encodeIfPresent(conditionStrength, forKey: .conditionStrength)
    }
}

/// One entry of a composition plan. The wire shape is a single object: it is an audio
/// reference when it carries `song_id`, a generation chunk when it carries `text`, never both.
public enum MusicPlanChunk: Codable, Equatable, Hashable, Sendable {
    case audioReference(MusicAudioRange)
    case generation(MusicGenerationChunk)

    private enum ProbeKeys: String, CodingKey {
        case songId = "song_id"
        case text
    }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: ProbeKeys.self)
        let hasSongId = probe.contains(.songId)
        let hasText = probe.contains(.text)
        guard hasSongId != hasText else {
            throw DecodingError.dataCorruptedError(
                forKey: .text, in: probe,
                debugDescription:
                    "A plan chunk is either an audio reference (song_id + range) or a generation chunk (text + duration_ms)"
            )
        }
        if hasSongId {
            self = .audioReference(try MusicAudioRange(from: decoder))
        } else {
            self = .generation(try MusicGenerationChunk(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .audioReference(let range): try range.encode(to: encoder)
        case .generation(let chunk): try chunk.encode(to: encoder)
        }
    }

    /// How long this chunk contributes to the finished piece.
    public var durationMilliseconds: Int64 {
        switch self {
        case .audioReference(let range): range.lengthMilliseconds
        case .generation(let chunk): chunk.durationMilliseconds
        }
    }

    public var isAudioReference: Bool {
        if case .audioReference = self { return true }
        return false
    }
}

/// The console-owned timeline for a music take (server #200). Its total length must cover the
/// dialog and stay within ElevenLabs' limits; `validationProblems` reproduces the server's
/// checks so the editor can complain before a request is sent.
public struct MusicCompositionPlan: Codable, Equatable, Hashable, Sendable {
    public var chunks: [MusicPlanChunk]

    public init(chunks: [MusicPlanChunk]) {
        self.chunks = chunks
    }

    public var totalDurationMilliseconds: Int64 {
        chunks.reduce(0) { $0 + $1.durationMilliseconds }
    }

    /// Start offset of each chunk within the piece, in order.
    public var chunkStartOffsets: [Int64] {
        var offsets: [Int64] = []
        var cursor: Int64 = 0
        for chunk in chunks {
            offsets.append(cursor)
            cursor += chunk.durationMilliseconds
        }
        return offsets
    }

    /// Human-readable reasons the server would reject this plan, in the order it checks them.
    /// Empty means the plan is sendable. `dialogDurationMilliseconds` is the accepted take's
    /// length when known; the coverage check is skipped when it isn't.
    public func validationProblems(dialogDurationMilliseconds: Int64?) -> [String] {
        var problems: [String] = []
        if chunks.isEmpty {
            problems.append("A plan needs at least one section.")
        } else if chunks.count > DialogLimits.maxMusicPlanChunks {
            problems.append("A plan can have at most \(DialogLimits.maxMusicPlanChunks) sections.")
        }
        for (index, chunk) in chunks.enumerated() {
            let label = "Section \(index + 1)"
            let length = chunk.durationMilliseconds
            if length < DialogLimits.minMusicChunkMilliseconds
                || length > DialogLimits.maxMusicChunkMilliseconds
            {
                problems.append(
                    "\(label) must last between \(Self.seconds(DialogLimits.minMusicChunkMilliseconds)) and \(Self.seconds(DialogLimits.maxMusicChunkMilliseconds))."
                )
            }
            switch chunk {
            case .audioReference(let range):
                if range.songId.isEmpty {
                    problems.append("\(label) references a take without a song id.")
                }
            case .generation(let generation):
                if generation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problems.append("\(label) needs a description.")
                } else if generation.text.utf8.count > DialogLimits.maxMusicChunkTextBytes {
                    problems.append(
                        "\(label)'s description exceeds \(DialogLimits.maxMusicChunkTextBytes) bytes."
                    )
                }
                if generation.positiveStyles.count > DialogLimits.maxMusicStyles
                    || generation.negativeStyles.count > DialogLimits.maxMusicStyles
                {
                    problems.append(
                        "\(label) can list at most \(DialogLimits.maxMusicStyles) styles per side."
                    )
                }
                if generation.conditionStrength != nil && generation.conditioningReference == nil {
                    problems.append(
                        "\(label) sets a condition strength without a reference take.")
                }
            }
        }
        let total = totalDurationMilliseconds
        if total > DialogLimits.maxMusicLengthMilliseconds {
            problems.append(
                "The plan runs \(Self.seconds(total)); the most the server allows is \(Self.seconds(DialogLimits.maxMusicLengthMilliseconds))."
            )
        }
        if let dialogDurationMilliseconds, total < dialogDurationMilliseconds {
            problems.append(
                "The plan runs \(Self.seconds(total)) but the dialog lasts \(Self.seconds(dialogDurationMilliseconds)); music must cover the speech."
            )
        }
        return problems
    }

    /// The plan for "keep the opening of this take, regenerate the rest": the first
    /// `keepMilliseconds` become audio-reference chunks of `songId` (split into pieces no
    /// longer than a chunk may be), a section straddling the keep point contributes its tail,
    /// and every later section is copied. The kept span is re-rendered by the model — close to
    /// the original, not sample-exact.
    ///
    /// Returns nil when the keep point would leave the reference or a tail shorter than the
    /// minimum chunk, or when it isn't inside the plan.
    public func keepingOpening(upTo keepMilliseconds: Int64, of songId: String)
        -> MusicCompositionPlan?
    {
        let minimum = DialogLimits.minMusicChunkMilliseconds
        let maximum = DialogLimits.maxMusicChunkMilliseconds
        guard keepMilliseconds >= minimum, keepMilliseconds < totalDurationMilliseconds else {
            return nil
        }

        var result: [MusicPlanChunk] = []
        let pieceCount = Int((keepMilliseconds + maximum - 1) / maximum)
        let pieceLength = keepMilliseconds / Int64(pieceCount)
        var cursor: Int64 = 0
        for piece in 0..<pieceCount {
            let end = piece == pieceCount - 1 ? keepMilliseconds : cursor + pieceLength
            result.append(
                .audioReference(
                    MusicAudioRange(
                        songId: songId, startMilliseconds: cursor, endMilliseconds: end)))
            cursor = end
        }

        var offset: Int64 = 0
        for chunk in chunks {
            let start = offset
            let end = offset + chunk.durationMilliseconds
            offset = end
            if end <= keepMilliseconds { continue }
            if start >= keepMilliseconds {
                result.append(chunk)
                continue
            }
            let tail = end - keepMilliseconds
            guard tail >= minimum else { return nil }
            switch chunk {
            case .generation(var generation):
                generation.durationMilliseconds = tail
                result.append(.generation(generation))
            case .audioReference(let range):
                result.append(
                    .audioReference(
                        MusicAudioRange(
                            songId: range.songId,
                            startMilliseconds: range.startMilliseconds + (keepMilliseconds - start),
                            endMilliseconds: range.endMilliseconds)))
            }
        }
        return MusicCompositionPlan(chunks: result)
    }

    /// The same plan with every generation section told to sound like `reference`. Audio
    /// references are left alone: they already are that sound.
    public func conditioned(on reference: MusicAudioRange, strength: MusicConditionStrength)
        -> MusicCompositionPlan
    {
        MusicCompositionPlan(
            chunks: chunks.map { chunk in
                guard case .generation(var generation) = chunk else { return chunk }
                generation.conditioningReference = reference
                generation.conditionStrength = strength
                return .generation(generation)
            })
    }

    /// The same plan with no conditioning references at all.
    public func unconditioned() -> MusicCompositionPlan {
        MusicCompositionPlan(
            chunks: chunks.map { chunk in
                guard case .generation(var generation) = chunk else { return chunk }
                generation.conditioningReference = nil
                generation.conditionStrength = nil
                return .generation(generation)
            })
    }

    private static func seconds(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1_000
        if seconds == seconds.rounded() {
            return "\(Int(seconds)) s"
        }
        return String(format: "%.1f s", seconds)
    }
}

extension MusicAudioRange {
    /// The longest span of a take that a single chunk may reference: the whole take, capped at
    /// the maximum chunk length.
    public static func referenceSpan(of songId: String, durationMilliseconds: Int64)
        -> MusicAudioRange
    {
        MusicAudioRange(
            songId: songId, startMilliseconds: 0,
            endMilliseconds: min(durationMilliseconds, DialogLimits.maxMusicChunkMilliseconds))
    }
}
