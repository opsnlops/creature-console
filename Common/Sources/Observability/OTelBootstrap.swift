import Foundation
import Logging
import OTel
import ServiceLifecycle

/// Bootstraps OpenTelemetry for logs, traces, and metrics.
///
/// Call this **before** creating any `Logger` instances. Returns services that must be
/// run in a `ServiceGroup` for telemetry data to be exported.
///
/// When `OTEL_EXPORTER_OTLP_ENDPOINT` is not set, OTel OTLP export is skipped entirely
/// to avoid slow startup from connection timeouts to localhost:4318. Console logging
/// still works normally via `StreamLogHandler`.
package func bootstrapObservability(serviceName: String) throws -> [any Service] {
    let hasEndpoint =
        ProcessInfo.processInfo.environment["OTEL_EXPORTER_OTLP_ENDPOINT"] != nil

    guard hasEndpoint else {
        // No endpoint configured — just set up console logging and return no services.
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }
        return []
    }

    var config = OTel.Configuration.default
    config.serviceName = serviceName

    // Bootstrap traces + metrics via OTel.bootstrap() with logs disabled.
    // This internally calls MetricsSystem.bootstrap() and InstrumentationSystem.bootstrap()
    // but skips LoggingSystem.bootstrap(), leaving us free to set it up with MultiplexLogHandler.
    config.logs.enabled = false
    let otelService = try OTel.bootstrap(configuration: config)

    // Get the OTLP log exporter separately so we can combine it with console output.
    var logConfig = OTel.Configuration.default
    logConfig.serviceName = serviceName
    logConfig.traces.enabled = false
    logConfig.metrics.enabled = false
    let loggingBackend = try OTel.makeLoggingBackend(configuration: logConfig)

    // MultiplexLogHandler preserves console logging for local dev and journald
    // while also exporting structured logs to Honeycomb via OTLP.
    LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
            loggingBackend.factory(label),
            StreamLogHandler.standardError(label: label),
        ])
    }

    return [otelService, loggingBackend.service]
}
