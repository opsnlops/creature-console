import Common
import Foundation

private enum LightweightSettingsKeys {
    static let hostname = "lightweight.serverHostname"
    static let port = "lightweight.serverPort"
    static let useTLS = "lightweight.serverUseTLS"
    static let defaultCreatureId = "lightweight.defaultCreatureId"
    static let backendHostname = "lightweight.backendHostname"
    static let activeUniverse = "lightweight.activeUniverse"
    static let apiKey = "lightweight.proxyApiKey"
}

private let lightweightDefaultValues: [String: Any] = [
    LightweightSettingsKeys.hostname: "proxy.prod.chirpchirp.dev",
    LightweightSettingsKeys.port: 443,
    LightweightSettingsKeys.useTLS: true,
    LightweightSettingsKeys.defaultCreatureId: "",
    LightweightSettingsKeys.backendHostname: "",
    LightweightSettingsKeys.activeUniverse: 1,
    LightweightSettingsKeys.apiKey: "",
]

struct LightweightClientSettings: Equatable, Sendable {
    var hostname: String
    var port: Int
    var useTLS: Bool
    var defaultCreatureId: CreatureIdentifier
    var backendHostname: String?
    var apiKey: String
}

actor LightweightSettingsStore {
    static let shared = LightweightSettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: lightweightDefaultValues)
    }

    func currentSettings() -> LightweightClientSettings {
        let hostname =
            defaults.string(forKey: LightweightSettingsKeys.hostname)
            ?? lightweightDefaultValues[LightweightSettingsKeys.hostname] as? String
            ?? "proxy.prod.chirpchirp.dev"
        let backend = defaults.string(forKey: LightweightSettingsKeys.backendHostname)
        let port = defaults.integer(forKey: LightweightSettingsKeys.port)
        let useTLS = defaults.bool(forKey: LightweightSettingsKeys.useTLS)
        let creature = defaults.string(forKey: LightweightSettingsKeys.defaultCreatureId) ?? ""
        let apiKey = defaults.string(forKey: LightweightSettingsKeys.apiKey) ?? ""

        return LightweightClientSettings(
            hostname: hostname,
            port: port == 0 ? 443 : port,
            useTLS: useTLS,
            defaultCreatureId: creature,
            backendHostname: backend?.isEmpty == true ? nil : backend,
            apiKey: apiKey
        )
    }

    func update(settings: LightweightClientSettings) {
        defaults.set(settings.hostname, forKey: LightweightSettingsKeys.hostname)
        defaults.set(settings.port, forKey: LightweightSettingsKeys.port)
        defaults.set(settings.useTLS, forKey: LightweightSettingsKeys.useTLS)
        defaults.set(settings.defaultCreatureId, forKey: LightweightSettingsKeys.defaultCreatureId)
        defaults.set(
            settings.backendHostname ?? "",
            forKey: LightweightSettingsKeys.backendHostname)
        defaults.set(settings.apiKey, forKey: LightweightSettingsKeys.apiKey)
    }

    func authToken() -> String {
        defaults.string(forKey: LightweightSettingsKeys.apiKey) ?? ""
    }

    func setAuthToken(_ token: String) {
        defaults.set(token, forKey: LightweightSettingsKeys.apiKey)
    }

    func activeUniverse() -> UniverseIdentifier {
        let value = defaults.integer(forKey: LightweightSettingsKeys.activeUniverse)
        return value == 0 ? 1 : value
    }

    func setActiveUniverse(_ universe: UniverseIdentifier) {
        defaults.set(universe, forKey: LightweightSettingsKeys.activeUniverse)
    }
}
