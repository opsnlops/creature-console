import Foundation

/// Request body for `PUT /api/v1/fixture/{id}/universe`. The server validates
/// `universe` is in `[1, 63999]` (E1.31 range) and rejects `0` / out-of-range with 400.
public struct SetFixtureUniverseDTO: Codable, Sendable {
    public var universe: UInt32

    public init(universe: UInt32) {
        self.universe = universe
    }
}
