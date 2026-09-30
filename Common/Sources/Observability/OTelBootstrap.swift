import Foundation
import Logging
import OTel
import ServiceLifecycle

/// Guards `LoggingSystem.bootstrap` so it runs at most once per process.
///
/// `swift-log` hard-crashes (`Precondition failed: logging system can only be initialized
/// once per process`) on a second `LoggingSystem.bootstrap`. A one-shot CLI invocation only
/// bootstraps once, but multiple commands sharing a process — most notably the test bundle,
/// where every `tracedRun` calls `bootstrapObservability` — would otherwise trip the second
/// bootstrap and abort the whole run.
private let loggingBootstrapLock = NSLock()
private nonisolated(unsafe) var loggingHasBeenBootstrapped = false

/// Bootstraps the global `LoggingSystem` exactly once. Returns `true` if this call performed
/// the bootstrap, `false` if it was already done earlier in the process.
@discardableResult
private func bootstrapLoggingOnce(_ factory: @escaping @Sendable (String) -> any LogHandler)
    -> Bool
{
    loggingBootstrapLock.lock()
    defer { loggingBootstrapLock.unlock() }
    guard !loggingHasBeenBootstrapped else { return false }
    LoggingSystem.bootstrap(factory)
    loggingHasBeenBootstrapped = true
    return true
}

/// Bootstraps OpenTelemetry for logs, traces, and metrics.
///
/// Call this **before** creating any `Logger` instances. Returns services that must be
/// run in a `ServiceGroup` for telemetry data to be exported.
///
/// When `OTEL_EXPORTER_OTLP_ENDPOINT` is not set, OTel OTLP export is skipped entirely
/// to avoid slow startup from connection timeouts to localhost:4318. Console logging
/// still works normally via `StreamLogHandler`.
///
/// `exportOTLP: false` forces the console-only path even when an endpoint is set. The
/// short-lived `creature-cli` uses this: swift-otel 1.4.0's batch exporters abort the
/// process with a Swift task-allocator LIFO violation ("freed pointer was not the last
/// allocation") when a real export races the command's teardown (issue #14). Console
/// logging is unaffected; long-lived services keep OTLP export.
package func bootstrapObservability(serviceName: String, exportOTLP: Bool = true) throws
    -> [any Service]
{
    let hasEndpoint =
        ProcessInfo.processInfo.environment["OTEL_EXPORTER_OTLP_ENDPOINT"] != nil

    guard exportOTLP, hasEndpoint else {
        // No OTLP export — just set up console logging and return no services.
        bootstrapLoggingOnce { label in
            StreamLogHandler.standardError(label: label)
        }
        return []
    }

    return try bootstrapOTLP(
        serviceName: serviceName, exporter: nil,
        localLog: { StreamLogHandler.standardError(label: $0) })
}

/// Where telemetry goes, given in code rather than by `OTEL_EXPORTER_OTLP_*`: a GUI app started
/// by launchd never sees the shell's environment, so the Information Bridge keeps these in its
/// Settings. `endpoint` is the base, as `OTEL_EXPORTER_OTLP_ENDPOINT` would be.
public struct OTLPExporterSettings: Sendable, Equatable {
    public var endpoint: URL
    public var headers: [String: String]

    public init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }

    /// "https://api.honeycomb.io/v1/traces" from "https://api.honeycomb.io": the spec's
    /// derivation from a base endpoint. swift-otel uses an endpoint set in code as-is, so the
    /// signal's path is added here.
    public func endpoint(for signal: String) -> String {
        let base = endpoint.absoluteString
        return (base.hasSuffix("/") ? base : base + "/") + "v1/\(signal)"
    }

    /// Headers in the order OpenTelemetry wants them: sorted, so a restart sends the same.
    var headerPairs: [(String, String)] {
        headers.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// Bootstraps OpenTelemetry to an exporter given in code, with logs going to OTLP and to
/// `localLog` - the unified log, for an app. Returns the services that export; run them with
/// ``runTelemetry(_:)``. Like the environment path, it bootstraps logging at most once per
/// process.
public func bootstrapObservability(
    serviceName: String, exporter: OTLPExporterSettings,
    localLog: @escaping @Sendable (String) -> any LogHandler
) throws -> [any Service] {
    try bootstrapOTLP(serviceName: serviceName, exporter: exporter, localLog: localLog)
}

/// Runs the exporting services until the task is cancelled - for an app with no service group
/// of its own.
public func runTelemetry(_ services: [any Service]) async throws {
    guard !services.isEmpty else { return }
    let group = ServiceGroup(
        configuration: .init(
            services: services.map { .init(service: $0) },
            logger: Logger(label: "telemetry", factory: SwiftLogNoOpLogHandler.init)))
    try await group.run()
}

/// Both paths: `exporter` nil reads the endpoint from the environment, as the services do.
private func bootstrapOTLP(
    serviceName: String, exporter: OTLPExporterSettings?,
    localLog: @escaping @Sendable (String) -> any LogHandler
) throws -> [any Service] {
    func configured(_ configure: (inout OTel.Configuration) -> Void) -> OTel.Configuration {
        var config = OTel.Configuration.default
        config.serviceName = serviceName
        // Environment-variable diagnostics can contain exporter authentication headers.
        config.diagnosticLogger = .custom(
            Logger(label: "swift-otel", factory: SwiftLogNoOpLogHandler.init))
        if let exporter {
            config.traces.otlpExporter.endpoint = exporter.endpoint(for: "traces")
            config.traces.otlpExporter.headers = exporter.headerPairs
            config.metrics.otlpExporter.endpoint = exporter.endpoint(for: "metrics")
            config.metrics.otlpExporter.headers = exporter.headerPairs
            config.logs.otlpExporter.endpoint = exporter.endpoint(for: "logs")
            config.logs.otlpExporter.headers = exporter.headerPairs
        }
        configure(&config)
        return config
    }

    // Bootstrap traces + metrics via OTel.bootstrap() with logs disabled.
    // This internally calls MetricsSystem.bootstrap() and InstrumentationSystem.bootstrap()
    // but skips LoggingSystem.bootstrap(), leaving us free to set it up with MultiplexLogHandler.
    let otelService = try OTel.bootstrap(configuration: configured { $0.logs.enabled = false })

    // Get the OTLP log exporter separately so we can combine it with local output.
    let loggingBackend = try OTel.makeLoggingBackend(
        configuration: configured {
            $0.traces.enabled = false
            $0.metrics.enabled = false
        })

    // MultiplexLogHandler keeps the local log (stderr and journald for a service, the unified
    // log for an app) while also exporting structured logs to Honeycomb via OTLP. Guarded so a
    // second command in the same process doesn't re-bootstrap (which would crash).
    bootstrapLoggingOnce { label in
        MultiplexLogHandler([loggingBackend.factory(label), localLog(label)])
    }

    return [otelService, loggingBackend.service]
}
