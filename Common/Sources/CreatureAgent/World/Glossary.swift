import AsyncHTTPClient
import Foundation
import Logging
import Observability
import ServiceLifecycle
import Synchronization
import WorldCore

/// The world's whole glossary - what every kind of fact means - kept by the mind and refreshed
/// now and then, so the prompt's stable item can carry all of it, sorted, byte for byte the
/// same from call to call. Before this the prompt carried only the meanings of the kinds in
/// that envelope, and the block reshuffled with the facts: the prefix missed the provider's
/// cache on nearly every call ("We're only at a 2% cache rate and I know the envelope is
/// mostly the same between prompts"). The whole glossary is bigger, and cached at a fraction
/// of the price.
final class Glossary: Sendable, Service {
    private let worldURL: URL
    private let client: HTTPClient
    private let logger: Logger
    private let refreshEvery: Duration
    private let meanings = Mutex<[String: String]>([:])

    init(worldURL: URL, client: HTTPClient, logger: Logger, refreshEvery: Duration = .seconds(600))
    {
        self.worldURL = worldURL
        self.client = client
        self.logger = logger
        self.refreshEvery = refreshEvery
    }

    /// What the mind holds now: empty until the first refresh lands.
    func current() -> [String: String] {
        meanings.withLock { $0 }
    }

    /// Fetches the glossary once; a failure keeps what was held.
    func refresh() async {
        var url = worldURL
        url.append(path: "fact-kinds")
        do {
            let request = HTTPClientRequest(url: url.absoluteString)
            let response = try await client.execute(request, timeout: .seconds(20), logger: logger)
            let body = try await response.body.collect(upTo: 4 * 1_048_576)
            guard response.status == .ok else {
                throw WorldResponderError.unavailable(status: UInt(response.status.code))
            }
            let page = try WorldJSON.makeDecoder().decode(
                FactKindPage.self, from: Data(body.readableBytesView))
            let fetched = Dictionary(
                uniqueKeysWithValues: page.kinds.map { ($0.predicate, $0.meaning) })
            let changed = meanings.withLock { held in
                defer { held = fetched }
                return held != fetched
            }
            if changed {
                logger.info("Glossary refreshed", metadata: ["glossary.kinds": "\(fetched.count)"])
            }
        } catch {
            logger.warning(
                "Could not refresh the glossary; keeping what is held",
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
