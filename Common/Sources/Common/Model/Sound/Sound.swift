import Foundation
import Logging

public final class Sound: Identifiable, Hashable, Equatable, Codable, Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Sound")
    public let fileName: SoundIdentifier
    public let size: UInt32
    public let transcript: String
    public let lipsync: String
    /// Human scene title embedded in the file's provenance (dialog renders); empty otherwise.
    public let title: String
    /// The dialog script this render came from, if embedded; empty otherwise.
    public let sourceScriptId: String
    /// The full readable dialog text embedded in the file ("Speaker: line" per turn); empty otherwise.
    public let script: String
    /// Comma-separated ElevenLabs generation ids embedded in the file; empty otherwise.
    public let generationIds: String
    /// True when the file carries embedded (iXML) script text.
    public let hasEmbeddedScript: Bool
    /// True when the file carries embedded (iXML) lip-sync (mouth cues from the ElevenLabs alignment).
    public let hasEmbeddedLipsync: Bool

    /// The best name to show a human: the embedded scene title if there is one,
    /// otherwise the (often UUID) file name.
    public var displayName: String {
        title.isEmpty ? fileName : title
    }

    /// True when there's readable text for this sound — a sidecar transcript or
    /// embedded script.
    public var hasText: Bool {
        !transcript.isEmpty || hasEmbeddedScript
    }

    /// True when there's lip-sync for this sound — a sidecar Rhubarb file or
    /// embedded mouth cues.
    public var hasLipsync: Bool {
        !lipsync.isEmpty || hasEmbeddedLipsync
    }

    // Use the file name for the identifiable thing. Since these are files on the file system, all in the
    // same directory, it's the file name that makes them unique
    public var id: SoundIdentifier {
        return fileName
    }

    public enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case size
        case transcript
        case lipsync
        case title
        case sourceScriptId = "source_script_id"
        case script
        case generationIds = "generation_ids"
        case hasEmbeddedScript = "has_embedded_script"
        case hasEmbeddedLipsync = "has_embedded_lipsync"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(SoundIdentifier.self, forKey: .fileName)
        size = try container.decode(UInt32.self, forKey: .size)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        lipsync = try container.decodeIfPresent(String.self, forKey: .lipsync) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sourceScriptId = try container.decodeIfPresent(String.self, forKey: .sourceScriptId) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        generationIds = try container.decodeIfPresent(String.self, forKey: .generationIds) ?? ""
        hasEmbeddedScript =
            try container.decodeIfPresent(Bool.self, forKey: .hasEmbeddedScript) ?? false
        hasEmbeddedLipsync =
            try container.decodeIfPresent(Bool.self, forKey: .hasEmbeddedLipsync) ?? false
        logger.debug("Created a new Sound from init(from:)")
    }

    public init(
        fileName: SoundIdentifier,
        size: UInt32,
        transcript: String = "",
        lipsync: String = "",
        title: String = "",
        sourceScriptId: String = "",
        script: String = "",
        generationIds: String = "",
        hasEmbeddedScript: Bool = false,
        hasEmbeddedLipsync: Bool = false
    ) {
        self.fileName = fileName
        self.size = size
        self.transcript = transcript
        self.lipsync = lipsync
        self.title = title
        self.sourceScriptId = sourceScriptId
        self.script = script
        self.generationIds = generationIds
        self.hasEmbeddedScript = hasEmbeddedScript
        self.hasEmbeddedLipsync = hasEmbeddedLipsync
        logger.debug("Created a new Sound from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(size)
        hasher.combine(transcript)
        hasher.combine(lipsync)
        hasher.combine(title)
        hasher.combine(hasEmbeddedScript)
    }

    // The == operator
    public static func == (lhs: Sound, rhs: Sound) -> Bool {
        return lhs.fileName == rhs.fileName && lhs.size == rhs.size
            && lhs.transcript == rhs.transcript && lhs.lipsync == rhs.lipsync
            && lhs.title == rhs.title && lhs.sourceScriptId == rhs.sourceScriptId
            && lhs.script == rhs.script && lhs.generationIds == rhs.generationIds
            && lhs.hasEmbeddedScript == rhs.hasEmbeddedScript
            && lhs.hasEmbeddedLipsync == rhs.hasEmbeddedLipsync
    }
}

extension Sound {
    public static func mock() -> Sound {
        return Sound(fileName: "amazingSound.mp3", size: 3_409_834, transcript: "", lipsync: "")
    }
}
