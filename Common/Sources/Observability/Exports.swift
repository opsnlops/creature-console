// An app links Observability alone and traces and logs with the same types the services use:
// `Logger` from swift-log, `withSpan` and `Span` from swift-distributed-tracing.
@_exported import Logging
@_exported import Tracing
