import Foundation

/// Where one creature sits on a stage, and which way it faces.
///
/// ## Coordinate frame
///
/// ```
/// origin (0,0,0) = the listener's head, facing −Z.  Metres, Y-up, right-handed
///                  (the same axes AVAudioEngine uses — only the origin moved).
///
///   +x  listener's right          −x  listener's left
///   +y  above the listener's ears −y  below   (bird heads sit slightly negative)
///   −z  in front of the listener  +z  behind them
/// ```
///
/// The ±5 m box *is* the stage — there is no separate width/depth.
///
/// ## Ownership
///
/// The server validates `creature_id`, `x`, `y`, `z` and `yaw` and uses them for head aiming. Every
/// other key here is the Console's — the server stores and returns them verbatim without
/// interpreting them, which is what lets one document drive both spatial audio and head aiming
/// instead of two copies that drift.
public struct StagePlacement: Codable, Equatable, Hashable, Identifiable, Sendable {

    // MARK: Server-validated geometry

    public var creatureID: CreatureIdentifier
    /// Metres to the listener's right (negative = left). Clamped to ±`StageLimits.coordinateLimit`.
    public var x: Float
    /// Metres above the listener's ears (negative = below). Bird heads on low perches sit negative.
    public var y: Float
    /// Metres behind the listener (negative = in front of them).
    public var z: Float
    /// Absolute heading in the stage frame, in degrees — **not** relative to the listener.
    /// `0` faces +Z, `+90` faces +X (the listener's right), `180` faces away from the listener.
    /// Always stored normalized to `(−180, 180]`.
    public var yaw: Float

    // MARK: Console-owned extras (round-tripped verbatim by the server)

    /// Display name, cached so a stage renders without a creature-list round-trip.
    public var creatureName: String
    /// The RTP audio lane this creature speaks on, 1–16.
    public var audioChannel: Int
    /// Linear gain applied to this creature's lane in the spatial mix.
    public var gain: Float
    public var isMuted: Bool

    /// Keys written by a newer client that this one doesn't model, preserved so a round-trip
    /// through an older Console doesn't silently drop them.
    public var additionalFields: [String: JSONValue]

    public var id: CreatureIdentifier { creatureID }

    enum CodingKeys: String, CodingKey {
        case creatureID = "creature_id"
        case x
        case y
        case z
        case yaw
        case creatureName = "creature_name"
        case audioChannel = "audio_channel"
        case gain
        case isMuted = "muted"
    }

    public init(
        creatureID: CreatureIdentifier,
        creatureName: String = "",
        audioChannel: Int = 0,
        x: Float,
        y: Float = 0,
        z: Float,
        yaw: Float = 0,
        gain: Float = 1,
        isMuted: Bool = false,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.creatureID = creatureID
        self.creatureName = creatureName
        self.audioChannel = audioChannel
        self.x = x
        self.y = y
        self.z = z
        self.yaw = Self.normalizedYaw(yaw)
        self.gain = gain
        self.isMuted = isMuted
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureID = try container.decode(CreatureIdentifier.self, forKey: .creatureID)
        x = try container.decodeIfPresent(Float.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Float.self, forKey: .y) ?? 0
        z = try container.decodeIfPresent(Float.self, forKey: .z) ?? 0
        yaw = Self.normalizedYaw(try container.decodeIfPresent(Float.self, forKey: .yaw) ?? 0)
        creatureName = try container.decodeIfPresent(String.self, forKey: .creatureName) ?? ""
        audioChannel = try container.decodeIfPresent(Int.self, forKey: .audioChannel) ?? 0
        gain = try container.decodeIfPresent(Float.self, forKey: .gain) ?? 1
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false

        // Anything this client doesn't model rides along untouched, the same way the server
        // preserves our extras.
        let everything =
            (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        additionalFields = everything.filter { !known.contains($0.key) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureID, forKey: .creatureID)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
        try container.encode(yaw, forKey: .yaw)
        try container.encode(creatureName, forKey: .creatureName)
        try container.encode(audioChannel, forKey: .audioChannel)
        try container.encode(gain, forKey: .gain)
        try container.encode(isMuted, forKey: .isMuted)

        guard !additionalFields.isEmpty else { return }
        var passthrough = encoder.container(keyedBy: JSONCodingKey.self)
        for (key, value) in additionalFields {
            guard let codingKey = JSONCodingKey(stringValue: key) else { continue }
            try passthrough.encode(value, forKey: codingKey)
        }
    }

    /// Fold an angle in degrees into `(−180, 180]`, matching the server's `normalizeDegrees()`.
    ///
    /// The server normalizes on *read* but not on write, so a stage storing `370°` would display
    /// `370°` in the editor while the creature actually aims at `10°`. Normalizing here keeps the
    /// stored document and the rendered behavior in agreement.
    public static func normalizedYaw(_ degrees: Float) -> Float {
        guard degrees.isFinite else { return 0 }
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        if wrapped > 180 { wrapped -= 360 }
        // Fmod of a value just under 360 can land on exactly −180; fold the sign so −180 and +180
        // never both appear for the same physical heading.
        if wrapped == -180 { wrapped = 180 }
        return wrapped
    }
}

extension StagePlacement.CodingKeys: CaseIterable {}

/// A `CodingKey` that accepts any string, for re-emitting preserved unknown fields.
struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
