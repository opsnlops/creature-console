import Common
import Foundation
import Testing
import WorldCore

@testable import CreatureAppSupport

@Suite("World Viewer client")
struct WorldViewerClientTests {
    private let connection = CreatureServiceConnection(
        hostname: "fuzzball", port: 8001, usesTLS: false)

    @Test("Reads pages through /world/v1 with bounded, snake_case queries")
    func readsPagesWithBoundedQueries() async throws {
        let loader = RecordingLoader(
            response: WorldEventPage(events: [], nextSequence: 40, hasMore: false))
        let client = WorldViewerClient(connection: connection, loader: loader)

        let page = try await client.events(after: 40, limit: 50)

        #expect(page.nextSequence == 40)
        let request = try #require(await loader.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "http://fuzzball:8001/world/v1/events?after_sequence=40&limit=50")
    }

    @Test("Deliveries are read from the conversation's deliveries route")
    func readsDeliveries() async throws {
        let loader = RecordingLoader(
            response: CharacterDeliveryPage(deliveries: [], nextResponseID: nil, hasMore: false))
        let client = WorldViewerClient(connection: connection, loader: loader)
        let conversationID = try ConversationID(validating: "conversation:april-beaky")
        let after = try ResponseID(validating: "response:abc")

        _ = try await client.deliveries(in: conversationID, after: after, limit: 20)

        let request = try #require(await loader.lastRequest)
        #expect(
            request.url?.absoluteString
                == "http://fuzzball:8001/world/v1/conversations/conversation:april-beaky/deliveries?after_response_id=response:abc&limit=20"
        )
    }

    @Test("Proxy connections carry the API key and logical Host")
    func proxyHeaders() async throws {
        let loader = RecordingLoader(
            response: WorldHealth(
                status: "ok", service: "creature-world", buildVersion: "0.3.0", mongodb: "ok",
                schemaVersion: 1))
        let proxied = CreatureServiceConnection(
            hostname: "server.prod.chirpchirp.dev", port: 443, usesTLS: true,
            proxyHostname: "proxy.prod.chirpchirp.dev", proxyAPIKey: "secret")
        let client = WorldViewerClient(connection: proxied, loader: loader)

        let health = try await client.health()

        #expect(health.buildVersion == "0.3.0")
        let request = try #require(await loader.lastRequest)
        #expect(request.url?.host() == "proxy.prod.chirpchirp.dev")
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "Host") == "server.prod.chirpchirp.dev:443")
    }

    @Test("SSE frames become typed stream frames; comments and unknown events are skipped")
    func parsesStreamFrames() throws {
        let snapshot = WorldSnapshot(
            latestSequence: 7, facts: [], timers: [], factsTruncated: false, timersTruncated: false)
        let event = try WorldEventEnvelope(
            type: WorldEventType(validating: "test.observed"),
            occurredAt: Date(timeIntervalSince1970: 1_789_200_000),
            source: EventSource(id: SourceID(validating: "test:viewer"), kind: "test"),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
        let encoder = WorldJSON.makeEncoder()
        let body = """
            event: snapshot
            id: 7
            data: \(String(decoding: try encoder.encode(snapshot), as: UTF8.self))

            : keep-alive

            event: delta
            id: 8
            data: \(String(decoding: try encoder.encode(WorldDelta(event: event, changedFacts: [])), as: UTF8.self))

            event: something_new
            data: {}

            event: resnapshot_required
            data: {"error":"stream_unavailable","message":"reconnect"}

            """
        var parser = ServerSentEventFrameParser()
        var frames: [WorldStreamFrame] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            for frame in parser.feed(line: String(line)) {
                if let typed = try WorldViewerClient.frame(from: frame) {
                    frames.append(typed)
                }
            }
        }

        #expect(frames.count == 3)
        #expect(frames[0] == .snapshot(snapshot))
        guard case .delta(let delta) = frames[1] else {
            Issue.record("expected a delta, got \(frames[1])")
            return
        }
        #expect(delta.event.eventID == event.eventID)
        #expect(frames[2] == .resnapshotRequired)
    }
}

private actor RecordingLoader<Response: Encodable & Sendable>: HTTPDataLoading {
    private let encodedResponse: Data
    private(set) var lastRequest: URLRequest?

    init(response: Response) {
        encodedResponse = try! WorldJSON.makeEncoder().encode(response)
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (encodedResponse, response)
    }
}
