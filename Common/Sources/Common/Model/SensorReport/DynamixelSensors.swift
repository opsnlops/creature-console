import Foundation

/// Telemetry for a single Dynamixel servo on the bus
///
/// Mirrors the per-motor objects the server forwards in the
/// `dynamixel-sensor-report` message (one entry per servo on the bus).
public final class DynamixelSensors: Codable, Hashable, Identifiable, Sendable {

    /// A Dynamixel servo is uniquely identified on its bus by its `dxlId`,
    /// so we key `Identifiable` on that rather than a synthesized `UUID`.
    public var id: DynamixelIdentifier { dxlId }
    public let dxlId: DynamixelIdentifier
    public let temperatureF: Double
    public let presentLoad: Int
    public let voltageMv: Int
    public let voltageV: Double
    /// Raw encoder position (0–4095 for XC430-class servos). Optional: older controller
    /// firmware omits `present_position`, so `nil` means "this servo didn't report it"
    /// rather than position zero.
    public let presentPosition: Int?

    enum CodingKeys: String, CodingKey {
        case dxlId = "dxl_id"
        case temperatureF = "temperature_f"
        case presentLoad = "present_load"
        case voltageMv = "voltage_mv"
        case voltageV = "voltage_v"
        case presentPosition = "present_position"
    }

    public init(
        dxlId: DynamixelIdentifier, temperatureF: Double, presentLoad: Int, voltageMv: Int,
        voltageV: Double, presentPosition: Int? = nil
    ) {
        self.dxlId = dxlId
        self.temperatureF = temperatureF
        self.presentLoad = presentLoad
        self.voltageMv = voltageMv
        self.voltageV = voltageV
        self.presentPosition = presentPosition
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dxlId = try container.decode(DynamixelIdentifier.self, forKey: .dxlId)
        temperatureF = try container.decode(Double.self, forKey: .temperatureF)
        presentLoad = try container.decode(Int.self, forKey: .presentLoad)
        voltageMv = try container.decode(Int.self, forKey: .voltageMv)
        voltageV = try container.decode(Double.self, forKey: .voltageV)
        presentPosition = try container.decodeIfPresent(Int.self, forKey: .presentPosition)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dxlId, forKey: .dxlId)
        try container.encode(temperatureF, forKey: .temperatureF)
        try container.encode(presentLoad, forKey: .presentLoad)
        try container.encode(voltageMv, forKey: .voltageMv)
        try container.encode(voltageV, forKey: .voltageV)
        try container.encodeIfPresent(presentPosition, forKey: .presentPosition)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(dxlId)
        hasher.combine(temperatureF)
        hasher.combine(presentLoad)
        hasher.combine(voltageMv)
        hasher.combine(voltageV)
        hasher.combine(presentPosition)
    }

    public static func == (lhs: DynamixelSensors, rhs: DynamixelSensors) -> Bool {
        lhs.dxlId == rhs.dxlId && lhs.temperatureF == rhs.temperatureF
            && lhs.presentLoad == rhs.presentLoad && lhs.voltageMv == rhs.voltageMv
            && lhs.voltageV == rhs.voltageV && lhs.presentPosition == rhs.presentPosition
    }
}

extension DynamixelSensors {
    public static func mock() -> DynamixelSensors {
        return DynamixelSensors(
            dxlId: 1,
            temperatureF: 95.0,
            presentLoad: -10,
            voltageMv: 12000,
            voltageV: 12.0,
            presentPosition: 2048
        )
    }
}
