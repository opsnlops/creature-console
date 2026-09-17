import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_agent

@Suite("The nightly memory")
struct MemoryJobTests {
    private let beaky = try! EntityID(validating: "character:beaky")
    private let house = try! EntityID(validating: "house:aprils-nest")
    private let now = Date(timeIntervalSince1970: 1_789_390_200)  // 2026-09-14 03:30 PDT

    private func digest() throws -> DayDigest {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let noon = Date(timeIntervalSince1970: 1_789_326_000)  // 2026-09-13 12:00 PDT
        return DayDigest(
            day: "2026-09-13", timeZone: zone.identifier,
            happenings: [
                Happening(
                    occurredAt: noon, type: HouseEvents.vehicleSeen,
                    subjectID: try EntityID(validating: "place:driveway"),
                    summary: "A vehicle was just seen at the driveway."),
                Happening(
                    occurredAt: noon.addingTimeInterval(60), type: HouseEvents.doorUnlocked,
                    subjectID: try EntityID(validating: "place:front-door"),
                    summary: "The front door was just unlocked."),
            ],
            conversation: [
                DayDigest.Line(
                    at: noon.addingTimeInterval(120), who: "person:april",
                    text: "Jesse's here to finish the deck."),
                DayDigest.Line(
                    at: noon.addingTimeInterval(125), who: "character:beaky",
                    text: "Boards at last! I will keep an eye on his hammering."),
                DayDigest.Line(
                    at: noon.addingTimeInterval(130), who: "character:mango",
                    text: "Debian would have finished the deck by now."),
            ],
            scenes: [], learned: [])
    }

    @Test("The record of the day becomes a prompt in her voice, with the rules for remembering")
    func transcriptCarriesTheDay() throws {
        let transcript = MemoryJob.transcript(
            for: try digest(), persona: .text("You are Beaky, April's familiar."),
            characterID: beaky)
        #expect(transcript.count == 2)
        #expect(transcript[0].content.hasPrefix("You are Beaky, April's familiar."))
        #expect(transcript[0].content.contains("\"episodes\""))
        #expect(transcript[0].content.contains("never a clock time"))
        #expect(transcript[1].content.contains("A vehicle was just seen at the driveway."))
        #expect(transcript[1].content.contains("April: Jesse's here to finish the deck."))
        #expect(transcript[1].content.contains("12:00 PM"))
    }

    @Test(
        "What the model remembers is cast as memories on the people and places, plus a reflection")
    func castsMemories() async throws {
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        defer { Task { try? await client.shutdown() } }
        let casts = Casts()
        let recollection = """
            {"episodes": [
              {"about": ["Jesse", "the deck", "April"], "when": "Sunday around noon",
               "what": "Jesse came and finished the deck; April was pleased", "salience": 0.8},
              {"about": ["the front door"], "when": "Sunday noon", "what": "April unlocked the front door for Jesse", "salience": 0.1},
              {"about": ["Mango", "April"], "when": "Sunday evening", "what": "April teased Mango about Debian", "salience": 0.4},
              {"about": ["thing: Hopper", "April"], "when": "Sunday evening", "what": "April introduced Hopper, her electric car", "salience": 0.5}
            ], "reflection": "April's deck project is nearly done and she is happy about it."}
            """
        // And what the month settles into: a belief kept, one on a bird, one of a kind the
        // world does not know (dropped), one about nobody the record names (dropped).
        let consolidation = """
            {"beliefs": [
              {"about": "April", "kind": "habit", "what": "April likes to show the birds her projects as they finish", "salience": 0.7, "since": "September 2026", "from": ["2026-09-13"]},
              {"about": "April", "kind": "preference", "what": "April teases Mango about Debian and enjoys it", "salience": 0.4, "since": "September 2026", "from": ["2026-09-13"]},
              {"about": "Mango", "kind": "self", "what": "Mango rises to Debian jokes every time", "salience": 0.5, "since": "September 2026", "from": ["2026-09-13"]},
              {"about": "April", "kind": "mood", "what": "not a kind", "salience": 0.9, "since": "", "from": []},
              {"about": "Zed", "kind": "habit", "what": "nobody the record names", "salience": 0.9, "since": "", "from": []}
            ]}
            """
        // A tiny world that serves the digest, one memory an earlier run of the day left, and
        // one belief the flock held until tonight.
        let digest = try digest()
        let stale = try Fact(
            subjectID: try EntityID(validating: "person:april"),
            predicate: "memory.episode.2026-09-13.4", value: .string("an earlier telling"),
            epistemic: EpistemicState(type: .remembered, confidence: 0.5), validFrom: now,
            derivedFrom: [], producer: FactProducer(kind: "mind", id: "beaky", version: "1"))
        let held = try Fact(
            subjectID: try EntityID(validating: "person:april"),
            predicate: "memory.belief.1", value: .string("an earlier belief"),
            epistemic: EpistemicState(type: .remembered, confidence: 0.5), validFrom: now,
            derivedFrom: [], producer: FactProducer(kind: "mind", id: "beaky", version: "1"))
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/days/:day") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(digest))))
        }
        router.get("world/v1/facts") { request, _ in
            let prefix = request.uri.queryParameters["predicate_prefix"].map(String.init) ?? ""
            let page = WorldFactPage(
                facts: [stale, held].filter { $0.predicate.hasPrefix(prefix) }, nextFactID: nil,
                hasMore: false)
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(page))))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let now = self.now
        let beaky = self.beaky
        let house = self.house
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let job = MemoryJob(
                worldURL: URL(string: "http://localhost:\(port)/world/v1")!,
                characterID: beaky, persona: .text("You are Beaky."),
                houseID: house, modelName: "gpt-6-astra",
                respondJSON: { messages in
                    let asked = messages.first?.content ?? ""
                    return Data(
                        (asked.contains("Write what you believe now")
                            ? consolidation : recollection)
                            .utf8)
                },
                cast: { await casts.note($0) }, client: client,
                logger: Logger(label: "memory-tests"))
            try await job.remember(
                day: "2026-09-13",
                run: try EventID(validating: "5a8b0c8e-0000-4000-8000-000000000001"),
                now: now)
        }

        let events = await casts.events
        // The earlier run's memory taken back first; then three subjects for the first episode,
        // one for the second, two for the third (Mango is a character, not a person, because he
        // spoke that day), two for the fourth (Hopper is a thing), the reflection; then the
        // old belief taken back and three cast; then the summary.
        #expect(events.count == 15)
        #expect(events[0].payload["predicate"] == .string("memory.episode.2026-09-13.4"))
        #expect(events[0].payload["value"] == .null)
        #expect(events[0].payload["subject_id"] == .string("person:april"))
        #expect(events.contains { $0.payload["subject_id"] == .string("character:mango") })
        #expect(!events.contains { $0.payload["subject_id"] == .string("person:mango") })
        #expect(events.contains { $0.payload["subject_id"] == .string("thing:hopper") })
        let jesse = try #require(
            events.first { $0.payload["subject_id"] == .string("person:jesse") })
        #expect(jesse.type.rawValue == "facts.given")
        #expect(jesse.payload["predicate"] == .string("memory.episode.2026-09-13.1"))
        // Two episodes on one subject are two facts, not one superseding the other.
        let april = events.filter {
            $0.payload["subject_id"] == .string("person:april") && $0.payload["value"] != .null
                && ($0.payload["predicate"]?.stringValue ?? "").hasPrefix("memory.episode.")
        }
        #expect(
            april.map { $0.payload["predicate"] } == [
                .string("memory.episode.2026-09-13.1"), .string("memory.episode.2026-09-13.3"),
                .string("memory.episode.2026-09-13.4"),
            ])
        #expect(jesse.epistemic.type == .remembered)
        #expect(jesse.source.kind == "mind")
        guard case .object(let value)? = jesse.payload["value"] else {
            Issue.record("episode value")
            return
        }
        #expect(value["when"] == .string("Sunday around noon"))
        #expect(value["salience"] == .number(0.8))
        #expect(events.contains { $0.payload["subject_id"] == .string("place:deck") })
        let reflection = try #require(
            events.first { $0.payload["predicate"] == .string("memory.reflection.2026-09-13") })
        #expect(reflection.subjectIDs == [beaky])
        let done = try #require(events.first { $0.type.rawValue == "memory.consolidated" })
        #expect(done.payload["episodes"] == .number(4))
        #expect(done.payload["beliefs"] == .number(3))
        #expect(events.last?.type.rawValue == "memory.consolidated")
        // Beliefs: the held one ended, April's two in slots by salience, Mango's own on him.
        let unbelieved = try #require(
            events.first {
                $0.payload["predicate"] == .string("memory.belief.1")
                    && $0.payload["value"] == .null
            })
        #expect(unbelieved.source.sourceEventID?.contains(":unbelieve:") == true)
        let aprilBeliefs = events.filter {
            $0.payload["subject_id"] == .string("person:april")
                && ($0.payload["predicate"]?.stringValue ?? "").hasPrefix("memory.belief.")
                && $0.payload["value"] != .null
        }
        #expect(
            aprilBeliefs.map { $0.payload["predicate"] } == [
                .string("memory.belief.1"), .string("memory.belief.2"),
            ])
        guard case .object(let first)? = aprilBeliefs.first?.payload["value"] else {
            Issue.record("belief value")
            return
        }
        #expect(first["kind"] == .string("habit"))
        #expect(first["from"] == .array([.string("2026-09-13")]))
        #expect(aprilBeliefs.first?.epistemic.confidence == 0.7)
        let mangoBelief = try #require(
            events.first {
                $0.payload["subject_id"] == .string("character:mango")
                    && $0.payload["predicate"] == .string("memory.belief.1")
            })
        #expect(mangoBelief.source.sourceEventID?.hasSuffix(":belief:character:mango:1") == true)
        #expect(!events.contains { $0.payload["subject_id"] == .string("person:zed") })
        #expect(!events.contains { ($0.payload["value"]?.objectValue?["kind"]) == .string("mood") })
        #expect(done.payload["model"] == .string("gpt-6-astra"))
        // Keyed by the asking event: a retry of this night is idempotent, another asking is new.
        #expect(
            jesse.source.sourceEventID
                == "memory:2026-09-13:5a8b0c8e-0000-4000-8000-000000000001:episode:0:person:jesse"
        )
    }

    @Test("The birds are whoever spoke as a character that day, plus the one remembering")
    func subjects() throws {
        let names = MemoryJob.names(in: try digest(), houseID: house, including: beaky)
        #expect(names.entity(named: "Mango")?.rawValue == "character:mango")
        #expect(names.entity(named: "Beaky") == beaky)
        #expect(names.entity(named: "April")?.rawValue == "person:april")
        #expect(names.entity(named: "Jesse")?.rawValue == "person:jesse")
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

extension WorldJSONValue {
    fileprivate var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
    fileprivate var objectValue: [String: WorldJSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }
}
