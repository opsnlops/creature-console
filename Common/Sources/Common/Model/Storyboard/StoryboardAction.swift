import Foundation

/// What a storyboard tile does when tapped.
///
/// Encoded as a tagged object — `{ "type": "<discriminator>", …snake_case params }` — so the wire
/// format is self-describing and forward-compatible: an unrecognized future `type` decodes to
/// `.unknown(type:raw:)`, preserving the original JSON verbatim so it re-encodes losslessly. The
/// client never re-implements *how* an action runs; `StoryboardActionRunner` dispatches each case to
/// the shared facade. UUID-bearing params encode lowercased (the server matches ids case-sensitively).
///
/// `universe` params are optional — `nil` means "follow the active universe"
/// (`UserDefaults["activeUniverse"]`), resolved at run time.
public enum StoryboardAction: Codable, Equatable, Hashable, Sendable {
    case playAnimation(
        animationId: AnimationIdentifier, universe: Int?, interrupt: Bool, resumePlaylist: Bool)
    case adHocSpeech(creatureId: CreatureIdentifier, resumePlaylist: Bool)
    case liveControl(creatureId: CreatureIdentifier, universe: Int?)
    case startPlaylist(playlistId: PlaylistIdentifier, universe: Int?)
    case stopPlaylist(universe: Int?)
    case playSound(fileName: String)
    case renderDialog(scriptId: DialogScriptIdentifier)
    case fixtureOn(fixtureId: DmxFixtureIdentifier)
    case fixtureOff(fixtureId: DmxFixtureIdentifier)
    case fixturePattern(
        fixtureId: DmxFixtureIdentifier, patternId: FixturePatternIdentifier, stopAfterMs: UInt32?)
    case fixtureDetails(fixtureId: DmxFixtureIdentifier)
    /// An action `type` this build doesn't recognize. The raw JSON is preserved so it round-trips.
    case unknown(type: String, raw: [String: JSONValue])

    /// The wire discriminator for this action.
    public var typeName: String {
        switch self {
        case .playAnimation: return "play_animation"
        case .adHocSpeech: return "ad_hoc_speech"
        case .liveControl: return "live_control"
        case .startPlaylist: return "start_playlist"
        case .stopPlaylist: return "stop_playlist"
        case .playSound: return "play_sound"
        case .renderDialog: return "render_dialog"
        case .fixtureOn: return "fixture_on"
        case .fixtureOff: return "fixture_off"
        case .fixturePattern: return "fixture_pattern"
        case .fixtureDetails: return "fixture_details"
        case .unknown(let type, _): return type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case animationId = "animation_id"
        case creatureId = "creature_id"
        case playlistId = "playlist_id"
        case fileName = "file_name"
        case scriptId = "script_id"
        case fixtureId = "fixture_id"
        case patternId = "pattern_id"
        case stopAfterMs = "stop_after_ms"
        case universe
        case interrupt
        case resumePlaylist = "resume_playlist"
    }

    public init(from decoder: Decoder) throws {
        // Decode the whole object once as a generic map: robust to missing/extra keys and the basis
        // for verbatim preservation of unknown action types.
        let object = (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
        func string(_ key: String) -> String? {
            if case .string(let value)? = object[key] { return value }
            return nil
        }
        func number(_ key: String) -> Double? {
            if case .number(let value)? = object[key] { return value }
            return nil
        }
        func boolean(_ key: String) -> Bool? {
            if case .bool(let value)? = object[key] { return value }
            return nil
        }

        switch string("type") ?? "" {
        case "play_animation":
            self = .playAnimation(
                animationId: string("animation_id") ?? "",
                universe: number("universe").map { Int($0) },
                interrupt: boolean("interrupt") ?? false,
                resumePlaylist: boolean("resume_playlist") ?? true)
        case "ad_hoc_speech":
            self = .adHocSpeech(
                creatureId: string("creature_id") ?? "",
                resumePlaylist: boolean("resume_playlist") ?? true)
        case "live_control":
            self = .liveControl(
                creatureId: string("creature_id") ?? "",
                universe: number("universe").map { Int($0) })
        case "start_playlist":
            self = .startPlaylist(
                playlistId: string("playlist_id") ?? "",
                universe: number("universe").map { Int($0) })
        case "stop_playlist":
            self = .stopPlaylist(universe: number("universe").map { Int($0) })
        case "play_sound":
            self = .playSound(fileName: string("file_name") ?? "")
        case "render_dialog":
            self = .renderDialog(
                scriptId: string("script_id").flatMap(UUID.init(uuidString:)) ?? UUID())
        case "fixture_on":
            self = .fixtureOn(fixtureId: string("fixture_id") ?? "")
        case "fixture_off":
            self = .fixtureOff(fixtureId: string("fixture_id") ?? "")
        case "fixture_pattern":
            self = .fixturePattern(
                fixtureId: string("fixture_id") ?? "",
                patternId: string("pattern_id") ?? "",
                stopAfterMs: number("stop_after_ms").map { UInt32($0) })
        case "fixture_details":
            self = .fixtureDetails(fixtureId: string("fixture_id") ?? "")
        case let other:
            self = .unknown(type: other, raw: object)
        }
    }

    public func encode(to encoder: Encoder) throws {
        // Unknown actions round-trip their original JSON verbatim.
        if case .unknown(_, let raw) = self {
            var single = encoder.singleValueContainer()
            try single.encode(raw)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .playAnimation(let animationId, let universe, let interrupt, let resumePlaylist):
            try container.encode(animationId, forKey: .animationId)
            try container.encodeIfPresent(universe, forKey: .universe)
            try container.encode(interrupt, forKey: .interrupt)
            try container.encode(resumePlaylist, forKey: .resumePlaylist)
        case .adHocSpeech(let creatureId, let resumePlaylist):
            try container.encode(creatureId, forKey: .creatureId)
            try container.encode(resumePlaylist, forKey: .resumePlaylist)
        case .liveControl(let creatureId, let universe):
            try container.encode(creatureId, forKey: .creatureId)
            try container.encodeIfPresent(universe, forKey: .universe)
        case .startPlaylist(let playlistId, let universe):
            try container.encode(playlistId, forKey: .playlistId)
            try container.encodeIfPresent(universe, forKey: .universe)
        case .stopPlaylist(let universe):
            try container.encodeIfPresent(universe, forKey: .universe)
        case .playSound(let fileName):
            try container.encode(fileName, forKey: .fileName)
        case .renderDialog(let scriptId):
            try container.encode(scriptId.uuidString.lowercased(), forKey: .scriptId)
        case .fixtureOn(let fixtureId), .fixtureOff(let fixtureId), .fixtureDetails(let fixtureId):
            try container.encode(fixtureId, forKey: .fixtureId)
        case .fixturePattern(let fixtureId, let patternId, let stopAfterMs):
            try container.encode(fixtureId, forKey: .fixtureId)
            try container.encode(patternId, forKey: .patternId)
            try container.encodeIfPresent(stopAfterMs, forKey: .stopAfterMs)
        case .unknown:
            break  // handled above
        }
    }
}
