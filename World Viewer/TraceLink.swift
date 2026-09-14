import SwiftUI
import WorldCore

/// A W3C traceparent as a link straight into Honeycomb: the whole path from April's words
/// through the mind and the world to Creature Server, on one screen.
struct TraceLink: View {
    let trace: W3CTraceContext?

    static let honeycomb = "https://ui.honeycomb.io/ops-n--lops/environments/production/trace"

    var body: some View {
        if let traceID = Self.traceID(of: trace),
            let url = URL(string: "\(Self.honeycomb)?trace_id=\(traceID)")
        {
            Link(destination: url) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
            .help("Open this trace in Honeycomb")
        }
    }

    /// `00-<trace id>-<span id>-<flags>` → the trace id.
    static func traceID(of trace: W3CTraceContext?) -> String? {
        guard let parts = trace?.traceparent.split(separator: "-"), parts.count == 4,
            parts[1].count == 32
        else { return nil }
        return String(parts[1])
    }
}
