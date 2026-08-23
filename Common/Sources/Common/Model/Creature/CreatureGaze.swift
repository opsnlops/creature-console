import Foundation

/// One axis of a creature's head aiming, mapping a servo input to real-world degrees.
///
/// The two `degrees` values are the physical angle the head reaches at each end of the
/// input's travel, which is what lets the server turn "look at the listener" into a servo
/// position. They must be finite and different from each other — a zero-width range means
/// the axis can't aim.
///
/// Mirrors the server's `GazeAxis` (creature-server `Creature.cpp`). The server rejects
/// unknown keys inside a gaze axis, so this struct is exactly the wire shape.
public struct GazeAxis: Codable, Equatable, Hashable, Sendable {

    /// The name of one of this creature's ``Input``s. The server validates that it matches.
    public var input: String
    /// The angle, in degrees, the head reaches at the input's minimum.
    public var degreesAtMin: Float
    /// The angle, in degrees, the head reaches at the input's maximum.
    public var degreesAtMax: Float
    /// How much of the aim to apply while the creature is listening rather than speaking,
    /// 0…1. Absent means the server's default.
    public var listeningAmount: Float?

    enum CodingKeys: String, CodingKey {
        case input
        case degreesAtMin = "degrees_at_min"
        case degreesAtMax = "degrees_at_max"
        case listeningAmount = "listening_amount"
    }

    public init(
        input: String, degreesAtMin: Float, degreesAtMax: Float, listeningAmount: Float? = nil
    ) {
        self.input = input
        self.degreesAtMin = degreesAtMin
        self.degreesAtMax = degreesAtMax
        self.listeningAmount = listeningAmount
    }

    /// True when this axis describes a range the server will accept.
    public var isValid: Bool {
        guard !input.isEmpty, degreesAtMin.isFinite, degreesAtMax.isFinite,
            degreesAtMin != degreesAtMax
        else { return false }
        guard let listeningAmount else { return true }
        return listeningAmount.isFinite && listeningAmount >= 0 && listeningAmount <= 1
    }
}

/// A creature's head-aiming configuration — up to three axes, each optional.
///
/// The server omits an axis it has no value for and omits `gaze` entirely when no axis is
/// configured, so a creature with no head aiming has no `gaze` key at all rather than an
/// empty object.
public struct GazeConfig: Codable, Equatable, Hashable, Sendable {

    /// Left/right rotation.
    public var pan: GazeAxis?
    /// Up/down tilt.
    public var elevation: GazeAxis?
    /// Head tilt around the beak axis — the quizzical bird head-cock.
    public var cock: GazeAxis?

    enum CodingKeys: String, CodingKey {
        case pan
        case elevation
        case cock
    }

    public init(pan: GazeAxis? = nil, elevation: GazeAxis? = nil, cock: GazeAxis? = nil) {
        self.pan = pan
        self.elevation = elevation
        self.cock = cock
    }

    /// True when no axis is configured. Such a value is never encoded — the server treats an
    /// empty `gaze` object the same as no `gaze` at all.
    public var isEmpty: Bool {
        pan == nil && elevation == nil && cock == nil
    }

    /// The configured axes, labelled, in the order the server writes them.
    public var axes: [(name: String, axis: GazeAxis)] {
        var result: [(name: String, axis: GazeAxis)] = []
        if let pan { result.append(("Pan", pan)) }
        if let elevation { result.append(("Elevation", elevation)) }
        if let cock { result.append(("Cock", cock)) }
        return result
    }
}
