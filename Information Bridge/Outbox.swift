import Foundation
import WorldCore

/// The Bridge's durable outbox: every fact it learns is written here first, then delivered to
/// the world in order, at least once. A world that is down, a laptop that sleeps, a proxy that
/// blinks - the fact waits on disk and goes when it can. The world deduplicates on the source's
/// event id, so a retry that already landed is a no-op there.
actor Outbox {
    struct Pending: Codable, Equatable, Sendable {
        var event: WorldEventEnvelope
        var enqueuedAt: Date
        var attempts: Int
    }

    /// One line per delivered fact, for the window: what was said, never what it came from.
    struct Delivered: Codable, Equatable, Sendable, Identifiable {
        var id: EventID { event.eventID }
        var event: WorldEventEnvelope
        var deliveredAt: Date
        var attempts: Int
    }

    struct Status: Equatable, Sendable {
        var pending: Int = 0
        var delivered: Int = 0
        var lastDeliveredAt: Date?
        var lastError: String?
        var nextAttemptAt: Date?
        var recent: [Delivered] = []
    }

    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void

    static let maximumRecent = 50
    static let firstBackoff: Duration = .seconds(2)
    static let maximumBackoff: Duration = .seconds(300)

    private let file: URL
    private var pending: [Pending] = []
    private var status = Status()
    private var observers: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var wake: CheckedContinuation<Void, Never>?
    private var worker: Task<Void, Never>?

    init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "outbox.json")
        if let data = try? Data(contentsOf: file) {
            let saved = try WorldJSON.makeDecoder().decode(Saved.self, from: data)
            pending = saved.pending
            status.delivered = saved.delivered
            status.lastDeliveredAt = saved.lastDeliveredAt
            status.recent = saved.recent
        }
        status.pending = pending.count
    }

    /// Writes the fact down and wakes the deliverer.
    func enqueue(_ event: WorldEventEnvelope) throws {
        pending.append(Pending(event: event, enqueuedAt: Date(), attempts: 0))
        try save()
        status.pending = pending.count
        publish()
        wake?.resume()
        wake = nil
    }

    /// Delivers, in order, forever - until `stop()`. `cast` is the world's door.
    func start(cast: @escaping Cast) {
        guard worker == nil else { return }
        worker = Task { await self.run(cast: cast) }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        wake?.resume()
        wake = nil
    }

    var current: Status { status }

    /// Every change of status, newest last; the window watches this.
    func updates() -> AsyncStream<Status> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { _ in
                Task { await self.forget(id) }
            }
        }
    }

    private func forget(_ id: UUID) {
        observers[id] = nil
    }

    private func run(cast: Cast) async {
        var backoff = Self.firstBackoff
        while !Task.isCancelled {
            guard let next = pending.first else {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    wake = continuation
                }
                continue
            }
            do {
                try await cast(next.event)
                pending.removeFirst()
                status.delivered += 1
                status.lastDeliveredAt = Date()
                status.lastError = nil
                status.nextAttemptAt = nil
                status.recent.insert(
                    Delivered(event: next.event, deliveredAt: Date(), attempts: next.attempts + 1),
                    at: 0)
                status.recent = Array(status.recent.prefix(Self.maximumRecent))
                backoff = Self.firstBackoff
            } catch is CancellationError {
                return
            } catch {
                pending[0].attempts += 1
                status.lastError = "\(error)"
                status.nextAttemptAt = Date().addingTimeInterval(
                    TimeInterval(backoff.components.seconds))
                status.pending = pending.count
                publish()
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, Self.maximumBackoff)
                continue
            }
            status.pending = pending.count
            try? save()
            publish()
        }
    }

    private func publish() {
        for observer in observers.values {
            observer.yield(status)
        }
    }

    private struct Saved: Codable {
        var pending: [Pending]
        var delivered: Int
        var lastDeliveredAt: Date?
        var recent: [Delivered]
    }

    private func save() throws {
        let saved = Saved(
            pending: pending, delivered: status.delivered, lastDeliveredAt: status.lastDeliveredAt,
            recent: status.recent)
        try WorldJSON.makeEncoder().encode(saved).write(to: file, options: .atomic)
    }
}
