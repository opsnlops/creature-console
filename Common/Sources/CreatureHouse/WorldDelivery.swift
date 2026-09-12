import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import WorldCore

/// Posts house events to Creature World, and keeps the ones it could not deliver in a file
/// until it can: a World restart never loses a door opening. Events carry their own source
/// identity, so a replay after a partial failure is deduplicated by the world.
actor WorldDelivery {
    private let worldURL: URL
    private let client: HTTPClient
    private let outbox: URL
    private let logger: Logger
    private var pending: [WorldEventEnvelope] = []
    private(set) var delivered = 0

    static let maximumPending = 5_000

    init(worldURL: URL, client: HTTPClient, outboxPath: String, logger: Logger) {
        self.worldURL = worldURL
        self.client = client
        self.outbox = URL(fileURLWithPath: outboxPath)
        self.logger = logger
        let kept = Self.read(outbox, logger: logger)
        pending = kept
        if !kept.isEmpty {
            logger.info("Outbox has undelivered events", metadata: ["count": "\(kept.count)"])
        }
    }

    /// Deliver now; on failure, keep it and try again with the next flush.
    func deliver(_ event: WorldEventEnvelope) async {
        pending.append(event)
        if pending.count > Self.maximumPending {
            logger.warning("Outbox is full; dropping the oldest events")
            pending.removeFirst(pending.count - Self.maximumPending)
        }
        await flush()
    }

    /// Try everything pending, in order; stop at the first failure so order is kept.
    func flush() async {
        while let next = pending.first {
            do {
                try await post(next)
                pending.removeFirst()
                delivered += 1
            } catch {
                logger.warning(
                    "Could not deliver to the world; keeping it",
                    metadata: [
                        "error": "\(error)", "world.event_type": "\(next.type.rawValue)",
                        "outbox.pending": "\(pending.count)",
                    ])
                break
            }
        }
        write()
    }

    var pendingCount: Int { pending.count }

    private func post(_ event: WorldEventEnvelope) async throws {
        var request = HTTPClientRequest(
            url: worldURL.appendingPathComponent("events").absoluteString)
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(try WorldJSON.makeEncoder().encode(event))
        let response = try await client.execute(request, timeout: .seconds(15))
        // 202 accepted, 200 duplicate: both mean the world has it.
        guard response.status == .accepted || response.status == .ok else {
            let body = try await response.body.collect(upTo: 4_096)
            throw WorldDeliveryError.refused(UInt(response.status.code), String(buffer: body))
        }
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: outbox.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = WorldJSON.makeEncoder()
            let lines = try pending.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
                .write(to: outbox, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Could not write the outbox", metadata: ["error": "\(error)"])
        }
    }

    private static func read(_ outbox: URL, logger: Logger) -> [WorldEventEnvelope] {
        guard let contents = try? String(contentsOf: outbox, encoding: .utf8) else { return [] }
        let decoder = WorldJSON.makeDecoder()
        return contents.split(separator: "\n").compactMap { line in
            do {
                return try decoder.decode(WorldEventEnvelope.self, from: Data(line.utf8))
            } catch {
                logger.warning(
                    "Skipping an unreadable outbox line", metadata: ["error": "\(error)"])
                return nil
            }
        }
    }
}

enum WorldDeliveryError: Error, LocalizedError {
    case refused(UInt, String)
    var errorDescription: String? {
        switch self {
        case .refused(let code, let body): "Creature World answered HTTP \(code): \(body)"
        }
    }
}
