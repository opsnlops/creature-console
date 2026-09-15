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
        static let weatherOn = "informationBridgeWeatherOn"
        static let useMacLocation = "informationBridgeUseMacLocation"
        static let latitude = "informationBridgeLatitude"
        static let longitude = "informationBridgeLongitude"
        static let outsideID = "informationBridgeOutsideID"
        static let contactsOn = "informationBridgeContactsOn"
    }

    static let defaultHostname = "server.prod.chirpchirp.dev"
    static let defaultPort = 443
    static let defaultHouseID = try! EntityID(validating: "house:aprils-nest")
    static let defaultOutsideID = try! EntityID(validating: "place:outside")

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

    /// The place the sky is over, and where it is. Weather is off until April says where.
    struct Sky: Equatable, Sendable {
        var place: EntityID
        var latitude: Double
        var longitude: Double
    }

    var isWeatherOn: Bool { defaults.bool(forKey: Keys.weatherOn) }
    var isContactsOn: Bool { defaults.bool(forKey: Keys.contactsOn) }

    /// Whether the house is wherever this Mac is (the default) or at coordinates April typed.
    var usesMacLocation: Bool { defaults.object(forKey: Keys.useMacLocation) as? Bool ?? true }

    var outsideID: EntityID {
        (defaults.string(forKey: Keys.outsideID).flatMap(EntityID.init(rawValue:)))
            ?? Self.defaultOutsideID
    }

    /// The sky as configured by hand; nil when weather is off, this Mac's location is to be
    /// used instead, or nothing has been typed.
    var sky: Sky? {
        guard isWeatherOn, !usesMacLocation,
            let latitude = defaults.object(forKey: Keys.latitude) as? Double,
            let longitude = defaults.object(forKey: Keys.longitude) as? Double,
            latitude != 0 || longitude != 0
        else { return nil }
        return Sky(place: outsideID, latitude: latitude, longitude: longitude)
    }

    /// The last place this Mac was found, so a restart need not wait for a fix.
    var rememberedMacLocation: Sky? {
        guard let latitude = defaults.object(forKey: "informationBridgeMacLatitude") as? Double,
            let longitude = defaults.object(forKey: "informationBridgeMacLongitude") as? Double
        else { return nil }
        return Sky(place: outsideID, latitude: latitude, longitude: longitude)
    }

    func rememberMacLocation(latitude: Double, longitude: Double) {
        defaults.set(latitude, forKey: "informationBridgeMacLatitude")
        defaults.set(longitude, forKey: "informationBridgeMacLongitude")
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
