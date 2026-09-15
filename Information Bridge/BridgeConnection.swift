import Common
import CreatureAppSupport
import Foundation
import WorldCore

/// Where the Bridge delivers. Mirrors World Viewer's settings shape under its own keys; the
/// default is production, because the Bridge has one job and one world to tell.
@MainActor
final class BridgeConnection: Sendable {
    static let shared = BridgeConnection()

    enum Keys {
        static let address = "informationBridgeServerAddress"
        static let port = "informationBridgeServerPort"
        static let useTLS = "informationBridgeServerUseTLS"
        static let useProxy = "informationBridgeServerUseProxy"
        static let proxyHost = "informationBridgeServerProxyHost"
        static let houseID = "informationBridgeHouseID"
    }

    static let defaultHostname = "server.prod.chirpchirp.dev"
    static let defaultPort = 443
    static let defaultHouseID = try! EntityID(validating: "house:aprils-nest")

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

    /// The house the Bridge speaks for: the subject of what it learns about the home.
    var houseID: EntityID {
        (defaults.string(forKey: Keys.houseID).flatMap(EntityID.init(rawValue:)))
            ?? Self.defaultHouseID
    }

    func client() throws -> WorldViewerClient {
        WorldViewerClient(connection: settings().connection(proxyAPIKey: try keyStore?.apiKey()))
    }

    func settings() -> CreatureServiceSettings {
        CreatureServiceSettings(
            hostname: defaults.string(forKey: Keys.address) ?? Self.defaultHostname,
            port: defaults.object(forKey: Keys.port) as? Int ?? Self.defaultPort,
            usesTLS: defaults.object(forKey: Keys.useTLS) as? Bool ?? true,
            usesProxy: defaults.bool(forKey: Keys.useProxy),
            proxyHostname: defaults.string(forKey: Keys.proxyHost) ?? "proxy.prod.chirpchirp.dev"
        )
    }
}
