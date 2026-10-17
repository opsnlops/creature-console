import AsyncHTTPClient
import Foundation
import Logging
import Observability
import ServiceLifecycle
import Synchronization
import WorldCore

/// Something of the world's a mind holds and refreshes now and then, for the prompt's stable
/// item: kept byte for byte the same between refreshes, so the provider's cache serves it.
/// Empty (`initial`) until the first refresh lands; a failed refresh keeps what is held.
final class WorldReference<Value: Equatable & Sendable>: Sendable, Service {
    private let worldURL: URL
    private let path: [String]
    private let label: String
    private let client: HTTPClient
    private let logger: Logger
    private let refreshEvery: Duration
    private let read: @Sendable (Data) throws -> Value
    private let held: Mutex<Value>

    init(
        worldURL: URL, path: [String], label: String, initial: Value, client: HTTPClient,
        logger: Logger, refreshEvery: Duration = .seconds(600),
        read: @escaping @Sendable (Data) throws -> Value
    ) {
        self.worldURL = worldURL
        self.path = path
        self.label = label
        self.client = client
        self.logger = logger
        self.refreshEvery = refreshEvery
        self.read = read
        self.held = Mutex(initial)
    }

    /// What the mind holds now.
    func current() -> Value {
        held.withLock { $0 }
    }

    /// Fetches it once; a failure keeps what was held.
    func refresh() async {
        var url = worldURL
        for part in path { url.append(path: part) }
        do {
            let request = HTTPClientRequest(url: url.absoluteString)
            let response = try await client.execute(request, timeout: .seconds(20), logger: logger)
            let body = try await response.body.collect(upTo: 4 * 1_048_576)
            guard response.status == .ok else {
                throw WorldResponderError.unavailable(status: UInt(response.status.code))
            }
            let fetched = try read(Data(body.readableBytesView))
            let changed = held.withLock { held in
                defer { held = fetched }
                return held != fetched
            }
            if changed { logger.info("Refreshed the \(label) from the world") }
        } catch {
            logger.warning(
                "Could not refresh the \(label); keeping what is held",
                metadata: ["error": "\(error)"])
        }
    }

    func run() async throws {
        await refresh()
        try await PeriodicHealthCheckService(
            interval: refreshEvery,
            operation: { await self.refresh() },
            shutdown: {}
        ).run()
    }
}

/// The world's whole glossary - what every kind of fact means - so the prompt's stable item
/// can carry all of it, sorted, byte for byte the same from call to call. Before this the
/// prompt carried only the meanings of the kinds in that envelope, and the block reshuffled
/// with the facts: the prefix missed the provider's cache on nearly every call ("We're only at
/// a 2% cache rate and I know the envelope is mostly the same between prompts"). The whole
/// glossary is bigger, and cached at a fraction of the price.
typealias Glossary = WorldReference<[String: String]>

extension WorldReference where Value == [String: String] {
    convenience init(worldURL: URL, client: HTTPClient, logger: Logger) {
        self.init(
            worldURL: worldURL, path: ["fact-kinds"], label: "glossary", initial: [:],
            client: client, logger: logger
        ) { data in
            let page = try WorldJSON.makeDecoder().decode(FactKindPage.self, from: data)
            return Dictionary(uniqueKeysWithValues: page.kinds.map { ($0.predicate, $0.meaning) })
        }
    }
}

/// Who decides that April is asking the house for a scene, and the house's scenes (#240); nil
/// until the world has said, or from a world without the endpoint - the bird asks nothing.
typealias HouseAskReference = WorldReference<HouseAsks?>

extension WorldReference where Value == HouseAsks? {
    convenience init(worldURL: URL, client: HTTPClient, logger: Logger) {
        self.init(
            worldURL: worldURL, path: ["house", "asks"], label: "house's scenes", initial: nil,
            client: client, logger: logger
        ) { data in try WorldJSON.makeDecoder().decode(HouseAsks.self, from: data) }
    }
}
