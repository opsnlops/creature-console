/// The OpenTelemetry conventions for the Model Context Protocol
/// (open-telemetry/semantic-conventions-genai, `docs/gen-ai/mcp.md`, Development): the names
/// both ends of WorldMCP use - the world serving it, a mind calling it - so a look-up reads as
/// one trace across the two processes (#230).
public enum MCPTelemetry {
    public enum Key {
        public static let methodName = "mcp.method.name"
        public static let protocolVersion = "mcp.protocol.version"
        public static let sessionID = "mcp.session.id"
        public static let jsonRPCRequestID = "jsonrpc.request.id"
        public static let rpcResponseStatusCode = "rpc.response.status_code"
        public static let toolName = "gen_ai.tool.name"
        public static let operationName = "gen_ai.operation.name"
        public static let networkTransport = "network.transport"
        public static let networkProtocolName = "network.protocol.name"
        public static let serverAddress = "server.address"
        public static let serverPort = "server.port"
        public static let errorType = "error.type"
    }

    public enum Metric {
        public static let clientOperationDuration = "mcp.client.operation.duration"
        public static let serverOperationDuration = "mcp.server.operation.duration"
    }

    /// The trace rides in the request's `params._meta`, unprefixed (SEP-414): HTTP's own
    /// headers carry only the HTTP request, and one HTTP request is not one MCP message.
    public static let traceKeys = ["traceparent", "tracestate", "baggage"]

    /// The spec's bucket bounds, in seconds, for both operation histograms.
    public static let durationHistogramBuckets: [String: [Duration]] = {
        let bounds = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 30, 60, 120, 300]
        let buckets = bounds.map { Duration.nanoseconds(Int64(($0 * 1e9).rounded())) }
        return [
            Metric.clientOperationDuration: buckets,
            Metric.serverOperationDuration: buckets,
        ]
    }()

    /// `tools/call query_entity`, or the method alone when there is no low-cardinality
    /// target.
    public static func spanName(method: String, tool: String?) -> String {
        tool.map { "\(method) \($0)" } ?? method
    }
}
