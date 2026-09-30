import CreatureAppSupport
import Foundation
import LoggingOSLog
import Observability

/// Where the Bridge's traces and logs go. The services read `OTEL_EXPORTER_OTLP_*`; an app
/// started by launchd never sees the shell's environment, so the Bridge keeps its exporter in
/// Settings - the endpoint in defaults, the API key in the Keychain beside the mail passwords.
/// Plan: `docs/information-bridge-telemetry-plan.md`.
enum BridgeTelemetry {
    enum Keys {
        static let on = "telemetry.on"
        static let endpoint = "telemetry.endpoint"
    }

    static let serviceName = "information-bridge"
    static let defaultEndpoint = "https://api.honeycomb.io"
    static let keychainService = "io.opsnlops.Information-Bridge.telemetry"
    static let keychainAccount = "honeycomb-api-key"

    /// The Honeycomb key, or nil when none was set. A Keychain that will not answer is an
    /// error, not an absence.
    static func apiKey() throws -> String? {
        try CreatureKeychainItem(service: keychainService, account: keychainAccount).value()
    }

    static func setAPIKey(_ key: String) throws {
        let item = try CreatureKeychainItem(service: keychainService, account: keychainAccount)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try item.set(trimmed.isEmpty ? nil : trimmed)
        // Readable at launch after a reboot, before anyone unlocks the laptop.
        if !trimmed.isEmpty { try item.allowReadingWhileLocked() }
    }

    /// The exporter Settings describe, or nil when telemetry is off or incomplete.
    static func exporter(defaults: UserDefaults = .standard, apiKey: String?)
        -> OTLPExporterSettings?
    {
        guard defaults.bool(forKey: Keys.on), let apiKey, !apiKey.isEmpty else { return nil }
        let text =
            (defaults.string(forKey: Keys.endpoint) ?? defaultEndpoint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text.isEmpty ? defaultEndpoint : text),
            url.scheme == "https" || url.scheme == "http", url.host() != nil
        else { return nil }
        return OTLPExporterSettings(endpoint: url, headers: ["x-honeycomb-team": apiKey])
    }

    /// Once, at launch, before any `Logger` is made: logging to the unified log always, and to
    /// Honeycomb as well when Settings say so. The returned task runs the exporters for the
    /// life of the app. Changing Settings takes effect at the next launch.
    @discardableResult
    static func start() -> Task<Void, Never>? {
        let exporter = exporter(apiKey: try? apiKey())
        guard let exporter else {
            LoggingSystem.bootstrap(LoggingOSLog.init)
            return nil
        }
        do {
            let services = try bootstrapObservability(
                serviceName: serviceName, exporter: exporter, localLog: LoggingOSLog.init)
            return Task.detached {
                do {
                    try await runTelemetry(services)
                } catch {
                    Logger(label: "telemetry").error(
                        "Telemetry stopped", metadata: ["error": "\(error)"])
                }
            }
        } catch {
            LoggingSystem.bootstrap(LoggingOSLog.init)
            Logger(label: "telemetry").error(
                "Could not start telemetry", metadata: ["error": "\(error)"])
            return nil
        }
    }
}
