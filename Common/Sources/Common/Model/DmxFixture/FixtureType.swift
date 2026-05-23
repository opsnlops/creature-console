import Foundation

/// The kind of DMX fixture this is. The server is liberal: unknown strings parse to
/// `.generic` so vendors can invent new device types without a client release.
public enum FixtureType: String, Codable, CaseIterable, Sendable {
    case light = "light"
    case smokeMachine = "smoke_machine"
    case fogger = "fogger"
    case generic = "generic"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = FixtureType(rawValue: raw) ?? .generic
    }
}
