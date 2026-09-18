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
        static let calendarOn = "informationBridgeCalendarOn"
        static let remindersOn = "informationBridgeRemindersOn"
        static let calendarsAllowed = "informationBridgeCalendarsAllowed"
        static let mailOn = "informationBridgeMailOn"
        static let mailSenders = "informationBridgeMailSenders"
        static let mailAccounts = "informationBridgeMailAccounts"
        static let messagesOn = "informationBridgeMessagesOn"
        static let messagesGroupChats = "informationBridgeMessagesGroupChats"
        /// The old free-text list of numbers, read once into `messagesSenders` and left.
        static let messagesExtraHandles = "informationBridgeMessagesExtraHandles"
        static let messagesSenders = "informationBridgeMessagesSenders"
        static let messagesLookbackDays = "informationBridgeMessagesLookbackDays"
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
    var isCalendarOn: Bool { defaults.bool(forKey: Keys.calendarOn) }
    var isRemindersOn: Bool { defaults.bool(forKey: Keys.remindersOn) }
    var isMailOn: Bool { defaults.bool(forKey: Keys.mailOn) }
    var isMessagesOn: Bool { defaults.bool(forKey: Keys.messagesOn) }
    var readsGroupChats: Bool { defaults.bool(forKey: Keys.messagesGroupChats) }
    /// How far the first read looks back; one day unless April says otherwise (a test reads
    /// further, and only what is still in force is cast).
    var messagesLookbackDays: Int {
        let days = defaults.integer(forKey: Keys.messagesLookbackDays)
        return days > 0 ? days : 1
    }
    /// Senders texts are read from even when no card is mapped to them: the carriers, and
    /// whatever April allows from the Senders window. Until she has saved a list, the
    /// built-in carriers, plus any numbers the old free-text field held (as "the carrier").
    var messagesSenders: [TextSender] {
        if let text = defaults.string(forKey: Keys.messagesSenders),
            let saved = try? JSONDecoder().decode([TextSender].self, from: Data(text.utf8))
        {
            return saved
        }
        let listed = (defaults.string(forKey: Keys.messagesExtraHandles) ?? "")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let known = Set(TextSender.defaults.map(\.id))
        return TextSender.defaults
            + listed.map { TextSender(handle: $0, name: "the carrier") }
            .filter { !known.contains($0.id) }
    }

    /// The whole list, as the window leaves it - a removed carrier stays removed.
    func setMessagesSenders(_ senders: [TextSender]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(senders) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: Keys.messagesSenders)
    }

    /// The IMAP accounts the Bridge reads; passwords are in the Keychain, not here.
    var mailAccounts: [IMAPAccount] {
        guard let data = defaults.data(forKey: Keys.mailAccounts),
            let accounts = try? JSONDecoder().decode([IMAPAccount].self, from: data)
        else { return [] }
        return accounts
    }

    func setMailAccounts(_ accounts: [IMAPAccount]) {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Keys.mailAccounts)
    }

    /// The carriers and merchants whose mail is read, one domain per line in Settings.
    var mailSenders: (carriers: [String], merchants: [String]) {
        let text = defaults.string(forKey: Keys.mailSenders) ?? ""
        let listed = text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !listed.isEmpty else {
            return (MailClassifier.defaultCarriers, MailClassifier.defaultMerchants)
        }
        let carriers = listed.filter { MailClassifier.defaultCarriers.contains($0) }
        return (carriers.isEmpty ? MailClassifier.defaultCarriers : carriers, listed)
    }

    /// The calendars April allows, by title; nil (nothing chosen yet) means all of them.
    var allowedCalendars: Set<String>? {
        guard let titles = defaults.stringArray(forKey: Keys.calendarsAllowed) else { return nil }
        return Set(titles)
    }

    func setAllowedCalendars(_ titles: Set<String>?) {
        if let titles {
            defaults.set(Array(titles).sorted(), forKey: Keys.calendarsAllowed)
        } else {
            defaults.removeObject(forKey: Keys.calendarsAllowed)
        }
    }

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
        WorldViewerClient(
            connection: settings().connection(proxyAPIKey: try keyStore?.apiKey()),
            loader: Self.session)
    }

    /// The Bridge's own session, with timeouts that mean it. `URLSession.shared` allows a
    /// request sixty seconds and a *resource* seven days: a connection left half-open when the
    /// laptop's lid closed hung the outbox's delivery indefinitely, and the outbox delivers
    /// in order, so the heartbeat behind it never went. Twenty seconds, then it is an error
    /// the outbox retries on a fresh connection.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

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
