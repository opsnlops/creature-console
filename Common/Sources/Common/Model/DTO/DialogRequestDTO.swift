import Foundation

/// Where a rendered dialog Animation is stored.
///
/// `adhoc` goes to a TTL collection (cron-cleaned); `permanent` goes to the main
/// animations collection. Required on every render — there is no server default.
public enum DialogPersistence: String, Codable, Sendable, CaseIterable {
    case adhoc
    case permanent
}

/// Request body for `POST /api/v1/animation/dialog` (async render → `202` + `JobCreatedResponse`).
///
/// Exactly one of `turns` or `scriptId` must be set — providing both, or neither, is a `400`.
/// Use ``fromTurns(_:persistence:autoplay:title:generationId:)`` or
/// ``fromScript(_:persistence:autoplay:title:generationId:)`` to construct a valid request.
public struct DialogRequest: Encodable, Sendable {

    public var turns: [DialogScriptTurn]?
    public var scriptId: DialogScriptIdentifier?
    public var persistence: DialogPersistence
    public var autoplay: Bool?
    public var title: String?
    public var generationId: DialogGenerationIdentifier?
    /// Which physical arrangement to render against, enabling stage-aware head aiming.
    ///
    /// Overrides the script's own `stageId`, which is how a travel rendition of a mainstage scene
    /// gets made. With neither set the server does no head aiming at all and the rendered frames
    /// are identical to a pre-stage render.
    public var stageId: StageIdentifier?

    enum CodingKeys: String, CodingKey {
        case turns
        case scriptId = "script_id"
        case persistence
        case autoplay
        case title
        case generationId = "generation_id"
        case stageId = "stage_id"
    }

    public init(
        turns: [DialogScriptTurn]?,
        scriptId: DialogScriptIdentifier?,
        persistence: DialogPersistence,
        autoplay: Bool? = nil,
        title: String? = nil,
        generationId: DialogGenerationIdentifier? = nil,
        stageId: StageIdentifier? = nil
    ) {
        self.turns = turns
        self.scriptId = scriptId
        self.persistence = persistence
        self.autoplay = autoplay
        self.title = title
        self.generationId = generationId
        self.stageId = stageId
    }

    /// Render an inline scene from a list of turns (no saved script).
    public static func fromTurns(
        _ turns: [DialogScriptTurn],
        persistence: DialogPersistence,
        autoplay: Bool? = nil,
        title: String? = nil,
        generationId: DialogGenerationIdentifier? = nil,
        stageId: StageIdentifier? = nil
    ) -> DialogRequest {
        DialogRequest(
            turns: turns, scriptId: nil, persistence: persistence,
            autoplay: autoplay, title: title, generationId: generationId, stageId: stageId)
    }

    /// Render a saved script by id. The server captures the script's turns at the moment
    /// of POST as a copy-on-write snapshot onto the resulting Animation.
    public static func fromScript(
        _ scriptId: DialogScriptIdentifier,
        persistence: DialogPersistence,
        autoplay: Bool? = nil,
        title: String? = nil,
        generationId: DialogGenerationIdentifier? = nil,
        stageId: StageIdentifier? = nil
    ) -> DialogRequest {
        DialogRequest(
            turns: nil, scriptId: scriptId, persistence: persistence,
            autoplay: autoplay, title: title, generationId: generationId, stageId: stageId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Only the populated side of the XOR is emitted. UUIDs go out lowercased to match
        // the server's case-sensitive id matching.
        try container.encodeIfPresent(turns, forKey: .turns)
        try container.encodeIfPresent(scriptId?.uuidString.lowercased(), forKey: .scriptId)
        try container.encode(persistence, forKey: .persistence)
        try container.encodeIfPresent(autoplay, forKey: .autoplay)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(
            generationId?.uuidString.lowercased(), forKey: .generationId)
        try container.encodeIfPresent(stageId?.uuidString.lowercased(), forKey: .stageId)
    }
}
