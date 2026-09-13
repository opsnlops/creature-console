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

    func serverURI() -> String {
        let settings = settings()
        let scheme = settings.usesTLS ? "https" : "http"
        return "\(scheme)://\(settings.hostname.lowercased()):\(settings.port)/communicator/v1"
    }

    func connection() throws -> CreatureServiceConnection {
        settings().connection(proxyAPIKey: try keyStore?.apiKey())
    }

    private func settings() -> CreatureServiceSettings {
        CreatureServiceSettings(
            hostname: defaults.string(forKey: "worldServerAddress") ?? "127.0.0.1",
            port: defaults.object(forKey: "worldServerPort") as? Int ?? 8_002,
            usesTLS: defaults.bool(forKey: "worldServerUseTLS"),
            usesProxy: defaults.bool(forKey: "worldServerUseProxy"),
            proxyHostname: defaults.string(forKey: "worldServerProxyHost")
                ?? "proxy.prod.chirpchirp.dev"
        )
    }

    func client() async throws -> any CommunicatorWorldClient {
        WorldConversationClient(
            connection: try connection(),
            endpoint: .communicatorGateway
        )
    }
}
