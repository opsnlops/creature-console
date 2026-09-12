import Common
import CreatureAppSupport
import Foundation
import WorldCore

/// Where World Viewer scries. Mirrors Beaky Communicator's settings shape under its own keys so
/// the Viewer can watch a development world while the Communicator talks to production.
@MainActor
final class WorldViewerConnection: Sendable {
    static let shared = WorldViewerConnection()

    enum Keys {
        static let address = "worldViewerServerAddress"
        static let port = "worldViewerServerPort"
        static let useTLS = "worldViewerServerUseTLS"
        static let useProxy = "worldViewerServerUseProxy"
        static let proxyHost = "worldViewerServerProxyHost"
        static let conversation = "worldViewerConversationID"
    }

    private let defaults: UserDefaults
    private let keyStore: ProxyAPIKeyStore?

    init(defaults: UserDefaults = .standard, keyStore: ProxyAPIKeyStore? = try? ProxyAPIKeyStore())
    {
        self.defaults = defaults
        self.keyStore = keyStore
    }

    /// The canonical world identity, independent of whether it is reached through the proxy.
    var worldURI: String {
        let settings = settings()
        let scheme = settings.usesTLS ? "https" : "http"
        return "\(scheme)://\(settings.hostname.lowercased()):\(settings.port)/world/v1"
    }

    var conversationID: ConversationID {
        (defaults.string(forKey: Keys.conversation).flatMap(ConversationID.init(rawValue:)))
            ?? Self.defaultConversationID
    }

    static let defaultConversationID = try! ConversationID(validating: "conversation:april-house")

    func connection() throws -> CreatureServiceConnection {
        settings().connection(proxyAPIKey: try keyStore?.apiKey())
    }

    func scryer() throws -> any WorldScrying {
        LiveWorldScryer(connection: try connection())
    }

    func settings() -> CreatureServiceSettings {
        CreatureServiceSettings(
            hostname: defaults.string(forKey: Keys.address) ?? "127.0.0.1",
            port: defaults.object(forKey: Keys.port) as? Int ?? 8_001,
            usesTLS: defaults.bool(forKey: Keys.useTLS),
            usesProxy: defaults.bool(forKey: Keys.useProxy),
            proxyHostname: defaults.string(forKey: Keys.proxyHost) ?? "proxy.prod.chirpchirp.dev"
        )
    }
}
