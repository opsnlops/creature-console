import Foundation

public typealias Instant = Date

public protocol WorldClock: Sendable {
    var now: Instant { get async }
    func sleep(until deadline: Instant) async throws
}

public struct SystemWorldClock: WorldClock {
    public init() {}

    public var now: Instant { get async { Date() } }

    public func sleep(until deadline: Instant) async throws {
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else { return }
        try await Task.sleep(for: .seconds(interval))
    }
}
