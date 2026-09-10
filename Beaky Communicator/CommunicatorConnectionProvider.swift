import Common
import CreatureAppSupport
import Foundation

@MainActor
final class CommunicatorConnectionProvider: CommunicatorWorldClientProviding, Sendable {
    static let shared = CommunicatorConnectionProvider()

    private let defaults: UserDefaults
    private let keyStore: ProxyAPIKeyStore?

    init(defaults: UserDefaults = .standard, keyStore: ProxyAPIKeyStore? = try? ProxyAPIKeyStore())
    {
        self.defaults = defaults
        self.keyStore = keyStore
    }

    func connection() throws -> CreatureServiceConnection {
        let settings = CreatureServiceSettings(
            hostname: defaults.string(forKey: "worldServerAddress") ?? "127.0.0.1",
            port: defaults.object(forKey: "worldServerPort") as? Int ?? 8_000,
            usesTLS: defaults.bool(forKey: "worldServerUseTLS"),
            usesProxy: defaults.bool(forKey: "worldServerUseProxy"),
            proxyHostname: defaults.string(forKey: "worldServerProxyHost")
                ?? "proxy.prod.chirpchirp.dev"
        )
        return settings.connection(proxyAPIKey: try keyStore?.apiKey())
    }

    func client() async throws -> any CommunicatorWorldClient {
        WorldConversationClient(connection: try connection())
    }
}
