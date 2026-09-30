import Foundation
import Testing

@testable import Observability

@Suite("Telemetry given in code, not the environment")
struct OTLPExporterSettingsTests {
    @Test("Each signal's endpoint is the base plus its path, as the spec derives it")
    func signalEndpoints() throws {
        let bare = OTLPExporterSettings(
            endpoint: try #require(URL(string: "https://api.honeycomb.io")))
        #expect(bare.endpoint(for: "traces") == "https://api.honeycomb.io/v1/traces")
        #expect(bare.endpoint(for: "logs") == "https://api.honeycomb.io/v1/logs")
        // A trailing slash or a path of its own - a collector behind a proxy - is kept.
        let slashed = OTLPExporterSettings(
            endpoint: try #require(URL(string: "http://collector.local:4318/otel/")))
        #expect(slashed.endpoint(for: "metrics") == "http://collector.local:4318/otel/v1/metrics")
    }

    @Test("Headers go out sorted, the same every launch")
    func headersSorted() throws {
        let settings = OTLPExporterSettings(
            endpoint: try #require(URL(string: "https://api.honeycomb.io")),
            headers: ["x-honeycomb-team": "key", "x-honeycomb-dataset": "bridge"])
        #expect(settings.headerPairs.map(\.0) == ["x-honeycomb-dataset", "x-honeycomb-team"])
    }

    @Test("A traceparent's trace id, and nothing from a malformed one")
    func traceIDs() {
        #expect(
            traceID(ofTraceparent: "00-68e09f1d38623f1fb1c7e3f80754a346-9080318972528e6b-01")
                == "68e09f1d38623f1fb1c7e3f80754a346")
        #expect(traceID(ofTraceparent: "not a traceparent") == nil)
    }
}
