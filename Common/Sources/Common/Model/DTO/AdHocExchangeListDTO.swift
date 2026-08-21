import Foundation

/// The server's response to `GET /animation/ad-hoc-stream/exchanges` — recent
/// streamed exchanges, newest first (creature-server#150).
public struct AdHocExchangeListDTO: Codable, Equatable, Sendable {
    public let count: UInt32
    public let items: [AdHocExchange]

    public init(count: UInt32, items: [AdHocExchange]) {
        self.count = count
        self.items = items
    }
}
