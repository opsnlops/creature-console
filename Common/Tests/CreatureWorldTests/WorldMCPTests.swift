import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import InMemoryTracing
import Logging
import Observability
import TestTracing
import Testing
import Tracing
import WorldCore

@testable import creature_world

@Suite("WorldMCP over Streamable HTTP")
struct WorldMCPTests {
    private let house = try! EntityID(validating: "house:aprils-nest")
    private let beaky = try! EntityID(validating: "character:beaky")

    @Test("initialize, tools, resources, and a read-only tool call, one POST each")
    func speaksMCP() async throws {
        let world = MCPWorld()
        let event = try WorldEventEnvelope(
            eventID: EventID(validating: "00000000-0000-0000-0000-000000000001"),
            type: WorldEventType(validating: "facts.given"),
            occurredAt: Date(timeIntervalSince1970: 1_789_500_000),
            source: EventSource(id: SourceID(validating: "bridge:mail"), kind: "bridge"),
            subjectIDs: [house], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["predicate": .string("visitor.expected")])
        let fact = try Fact(
            subjectID: house, predicate: "visitor.expected",
            value: .string("Quality Cleaning, Etc, Wednesday"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_500_000),
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(kind: "bridge", id: "mail", version: "1"))
        await world.set(facts: [fact], events: [event])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "mcp-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "mcp-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)

        try await application.test(.router) { client in
            func call(_ json: String) async throws -> (HTTPResponse.Status, WorldJSONValue?) {
                let response = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(string: json))
                let body =
                    response.body.readableBytes > 0
                    ? try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: response.body)
                    : nil
                return (response.status, body)
            }

            let (status, initialized) = try await call(
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#
            )
            #expect(status == .ok)
            #expect(initialized?["result"]?["protocolVersion"] == .string("2025-06-18"))
            #expect(initialized?["result"]?["serverInfo"]?["name"] == .string("creature-world"))

            // A notification gets 202 and no body.
            let (accepted, none) = try await call(
                #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
            #expect(accepted == .accepted)
            #expect(none == nil)

            let (_, tools) = try await call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
            guard case .array(let listed)? = tools?["result"]?["tools"] else {
                Issue.record("no tools")
                return
            }
            let names = listed.compactMap { $0["name"]?.stringValue }
            #expect(names.contains("inspect_world_state"))
            #expect(names.contains("explain_fact"))
            #expect(names.contains("query_character_perspective"))

            // The tool answers with text and structured content, from the same service.
            let (_, inspected) = try await call(
                #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"inspect_world_state","arguments":{"subject_id":"house:aprils-nest"}}}"#
            )
            guard case .array(let items)? = inspected?["result"]?["structuredContent"]?["items"]
            else {
                Issue.record("no structured content: \(String(describing: inspected))")
                return
            }
            #expect(items.count == 1)
            #expect(items[0]["predicate"] == .string("visitor.expected"))

            // Why: the fact and the event behind it.
            let (_, explained) = try await call(
                #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"explain_fact","arguments":{"subject_id":"house:aprils-nest","predicate":"visitor.expected"}}}"#
            )
            guard case .array(let events)? = explained?["result"]?["structuredContent"]?["events"]
            else {
                Issue.record("no explanation: \(String(describing: explained))")
                return
            }
            #expect(events.count == 1)
            #expect(events[0]["event_id"] == .string("00000000-0000-0000-0000-000000000001"))

            // Resources, by template.
            let (_, page) = try await call(
                #"{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"world://entities/house:aprils-nest"}}"#
            )
            guard case .array(let contents)? = page?["result"]?["contents"] else {
                Issue.record("no contents")
                return
            }
            #expect(contents.first?["uri"] == .string("world://entities/house:aprils-nest"))
            #expect(contents.first?["text"]?.stringValue?.contains("visitor.expected") == true)

            // Unknown things are JSON-RPC errors, not HTTP ones; GET is not a transport here.
            let (okStatus, unknown) = try await call(
                #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"drop_the_database"}}"#
            )
            #expect(okStatus == .ok)
            #expect(unknown?["error"]?["code"] == .number(-32601))
            let get = try await client.execute(uri: "/world/mcp", method: .get)
            #expect(get.status == .methodNotAllowed)
        }
    }

    @Test("Each MCP message is a SERVER span by the MCP conventions; a refusal says its code")
    func tracesEachMessage() async throws {
        _ = testTracer
        let world = MCPWorld()
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "mcp-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "mcp-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)
        let asked = "trace-\(UUID().uuidString)"
        let refused = "refused-\(UUID().uuidString)"
        try await application.test(.router) { client in
            for json in [
                #"{"jsonrpc":"2.0","id":"\#(asked)","method":"tools/call","params":{"name":"inspect_world_state","arguments":{"subject_id":"house:aprils-nest"},"_meta":{"audience":"minds","traceparent":"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}}}"#,
                #"{"jsonrpc":"2.0","id":"\#(refused)","method":"tools/call","params":{"name":"drop_the_database"}}"#,
            ] {
                _ = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(string: json))
            }
        }
        func span(_ id: String) throws -> FinishedInMemorySpan {
            try #require(
                testTracer.finishedSpans.first {
                    $0.attributes.get(MCPTelemetry.Key.jsonRPCRequestID) == .string(id)
                })
        }
        let served = try span(asked)
        #expect(served.operationName == "tools/call inspect_world_state")
        #expect(served.kind == .server)
        #expect(served.attributes.get(MCPTelemetry.Key.methodName) == .string("tools/call"))
        #expect(
            served.attributes.get(MCPTelemetry.Key.toolName) == .string("inspect_world_state"))
        #expect(served.attributes.get(MCPTelemetry.Key.operationName) == .string("execute_tool"))
        #expect(
            served.attributes.get(MCPTelemetry.Key.protocolVersion)
                == .string(WorldMCP.protocolVersion))
        #expect(served.attributes.get(MCPTelemetry.Key.errorType) == nil)

        let failed = try span(refused)
        #expect(failed.operationName == "tools/call drop_the_database")
        #expect(failed.attributes.get(MCPTelemetry.Key.errorType) == .string("-32601"))
        #expect(failed.attributes.get(MCPTelemetry.Key.rpcResponseStatusCode) == .string("-32601"))
        #expect(failed.status?.code == .error)
    }

    @Test("The caller's trace is read from params._meta; none, or a malformed one, is none")
    func readsTheCallersTrace() throws {
        let traced: WorldJSONValue = .object([
            "_meta": .object([
                "traceparent": .string("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
            ])
        ])
        #expect(WorldMCP.callerContext(in: traced) != nil)
        #expect(WorldMCP.callerContext(in: .object([:])) == nil)
        #expect(
            WorldMCP.callerContext(
                in: .object(["_meta": .object(["traceparent": .string("not a trace")])])) == nil)
    }

    @Test(
        "A tool takes a name the world knows in place of an id; a stranger gets a refusal with the id's shape"
    )
    func namesResolve() async throws {
        let world = MCPWorld()
        let tamara = try EntityID(validating: "person:tamara")
        let fact = try Fact(
            subjectID: tamara, predicate: "contact.name", value: .string("Tamara"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_500_000), derivedFrom: [],
            producer: FactProducer(kind: "bridge", id: "contacts", version: "1"))
        await world.set(facts: [fact], events: [])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "mcp-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "mcp-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)
        try await application.test(.router) { client in
            func call(_ json: String) async throws -> WorldJSONValue? {
                let response = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(string: json))
                return try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: response.body)
            }
            let found = try await call(
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"inspect_world_state","arguments":{"subject_id":"Tamara","limit":20}}}"#
            )
            guard case .array(let items)? = found?["result"]?["structuredContent"]?["items"]
            else {
                Issue.record("no items: \(String(describing: found))")
                return
            }
            #expect(items.first?["subject_id"] == .string("person:tamara"))
            // search_world: entities with the facts that matched, and the tool is listed.
            let searched = try await call(
                #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_world","arguments":{"query":"tamara"}}}"#
            )
            guard case .array(let hits)? = searched?["result"]?["structuredContent"]?["hits"]
            else {
                Issue.record("no hits: \(String(describing: searched))")
                return
            }
            #expect(hits.first?["entity_id"] == .string("person:tamara"))
            #expect(hits.first?["facts"]?.arrayCount == 1)
            let listed = try await call(#"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#)
            guard case .array(let tools)? = listed?["result"]?["tools"] else {
                Issue.record("no tools")
                return
            }
            #expect(tools.first?["name"] == .string("search_world"))
            let stranger = try await call(
                #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"query_entity","arguments":{"entity_id":"Zed"}}}"#
            )
            #expect(stranger?["error"]?["code"] == .number(-32602))
            #expect(
                stranger?["error"]?["message"]?.stringValue?.contains("ids look like person:tamara")
                    == true)
        }
    }

    @Test("A mind's call never sees a world-only fact; a person debugging sees everything")
    func audienceIsHonoured() async throws {
        let world = MCPWorld()
        let polly = try EntityID(validating: "person:polly")
        func fact(_ predicate: String, _ value: String) throws -> Fact {
            try Fact(
                subjectID: polly, predicate: predicate, value: .string(value),
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: Date(timeIntervalSince1970: 1_789_500_000), derivedFrom: [],
                producer: FactProducer(kind: "bridge", id: "contacts", version: "1"))
        }
        let name = try fact("contact.name", "Polly Jacobs")
        let phone = try fact("contact.phone", "1 937 555 0100")
        await world.set(facts: [name, phone], events: [])
        await world.set(worldOnly: ["contact.phone"])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "mcp-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "mcp-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)
        try await application.test(.router) { client in
            func call(_ json: String) async throws -> WorldJSONValue? {
                let response = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(string: json))
                return try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: response.body)
            }
            func predicates(_ value: WorldJSONValue?) -> [String] {
                guard case .array(let items)? = value else { return [] }
                return items.compactMap { $0["predicate"]?.stringValue }.sorted()
            }
            let asMind = #","_meta":{"audience":"minds"}}}"#
            // The phone is there for a person debugging...
            let debugging = try await call(
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"query_entity","arguments":{"entity_id":"person:polly"}}}"#
            )
            #expect(
                predicates(debugging?["result"]?["structuredContent"]?["facts"])
                    == ["contact.name", "contact.phone"])
            // ...and gone for a mind, from every tool that hands facts over.
            let mind = try await call(
                #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"query_entity","arguments":{"entity_id":"person:polly"}"#
                    + asMind
            )
            #expect(predicates(mind?["result"]?["structuredContent"]?["facts"]) == ["contact.name"])
            let searched = try await call(
                #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_world","arguments":{"query":"polly"}"#
                    + asMind
            )
            guard case .array(let hits)? = searched?["result"]?["structuredContent"]?["hits"]
            else {
                Issue.record("no hits")
                return
            }
            #expect(predicates(hits.first?["facts"]) == ["contact.name"])
            let inspected = try await call(
                #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"inspect_world_state","arguments":{"subject_id":"person:polly"}"#
                    + asMind
            )
            #expect(
                predicates(inspected?["result"]?["structuredContent"]?["items"]) == ["contact.name"]
            )
            // Why? on the phone itself: not for a mind.
            let why = try await call(
                #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"explain_fact","arguments":{"fact_id":""#
                    + phone.factID.rawValue + #""}"# + asMind
            )
            #expect(why?["error"]?["code"] == .number(-32002))
        }
    }

    @Test("A bird sees its own memories and those shared with it; never one kept private (#243)")
    func memoriesAreSharedByChoice() async throws {
        let world = MCPWorld()
        let april = try EntityID(validating: "person:april")
        let at = Date(timeIntervalSince1970: 1_789_500_000)
        func memory(_ bird: String, shared: Bool?) throws -> Fact {
            var value: [String: WorldJSONValue] = ["what": .string("\(bird) remembers the deck")]
            if let shared { value["shared"] = .bool(shared) }
            return try Fact(
                subjectID: april, predicate: "memory.episode.\(bird).2026-09-13.1",
                value: .object(value), epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: at, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        let facts = [
            try memory("beaky", shared: false),  // her own, kept to herself
            try memory("caroll", shared: false),  // Caroll's, kept to himself
            try memory("mango", shared: true),  // Mango's, shared
            try memory("kenny", shared: nil),  // from before the birds could choose: private
        ]
        func cast(_ predicate: String, _ value: WorldJSONValue) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: at,
                source: EventSource(id: SourceID(validating: "mind:caroll"), kind: "mind"),
                subjectIDs: [april], epistemic: EpistemicState(type: .remembered, confidence: 1),
                payload: [
                    "subject_id": .string(april.rawValue), "predicate": .string(predicate),
                    "value": value,
                ])
        }
        let events = [
            try cast(
                "memory.episode.caroll.2026-09-13.1",
                .object(["what": .string("private"), "shared": .bool(false)])),
            try cast(
                "memory.episode.mango.2026-09-13.1",
                .object(["what": .string("for the flock"), "shared": .bool(true)])),
            try cast(
                "memory.episode.beaky.2026-09-13.1", .object(["what": .string("her own")])),
            try cast("contact.phone", .string("1 937 555 0100")),
            try cast("visitor.expected", .string("Tuesday")),
            // Where April's phone is: the world's alone, never in a mind's timeline (#248).
            try WorldEventEnvelope(
                type: HouseEvents.personLocated, occurredAt: at,
                source: EventSource(
                    id: SourceID(validating: "home-assistant:person-april"),
                    kind: HouseEvents.sourceKind),
                subjectIDs: [april], epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: ["latitude": .number(40.0), "longitude": .number(-100.0)]),
        ]
        await world.set(facts: facts, events: events)
        await world.set(worldOnly: ["contact.phone"])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "mcp-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "mcp-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)
        try await application.test(.router) { client in
            func call(_ tool: String, _ arguments: String, mind: String?) async throws
                -> WorldJSONValue?
            {
                let meta =
                    mind.map { #"{"audience":"minds","mind":"\#($0)"}"# }
                    ?? #"{"audience":"minds"}"#
                let response = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(
                        string:
                            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments),"_meta":\#(meta)}}"#
                    ))
                return try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: response.body)
            }
            func owners(_ value: WorldJSONValue?) -> [String] {
                guard case .array(let items)? = value else { return [] }
                return items.compactMap { $0["predicate"]?.stringValue }
                    .compactMap { WorldFacts.memoryOwner(of: $0) }.sorted()
            }
            let entity = #"{"entity_id":"person:april"}"#
            let beaky = try await call("query_entity", entity, mind: "character:beaky")
            #expect(
                owners(beaky?["result"]?["structuredContent"]?["facts"]) == ["beaky", "mango"])
            let caroll = try await call("query_entity", entity, mind: "character:caroll")
            #expect(
                owners(caroll?["result"]?["structuredContent"]?["facts"]) == ["caroll", "mango"])
            // A mind that does not say which it is sees no bird's private memory.
            let unnamed = try await call("query_entity", entity, mind: nil)
            #expect(
                owners(unnamed?["result"]?["structuredContent"]?["facts"]) == ["mango"])
            // Search hands facts over too: the same gate.
            let searched = try await call(
                "search_world", #"{"query":"april"}"#, mind: "character:beaky")
            guard case .array(let hits)? = searched?["result"]?["structuredContent"]?["hits"]
            else {
                Issue.record("no hits")
                return
            }
            #expect(owners(hits.first?["facts"]) == ["beaky", "mango"])
            // The timeline carries the same values in its events: gated the same way, and a
            // world-only fact never reaches a mind through it either.
            let timeline = try await call(
                "query_timeline", #"{"after_sequence":0}"#, mind: "character:beaky")
            guard case .array(let kept)? = timeline?["result"]?["structuredContent"]?["items"]
            else {
                Issue.record("no timeline")
                return
            }
            #expect(
                !kept.contains { $0["type"]?.stringValue == HouseEvents.personLocated.rawValue })
            #expect(
                kept.compactMap { $0["payload"]?["predicate"]?.stringValue } == [
                    "memory.episode.mango.2026-09-13.1", "memory.episode.beaky.2026-09-13.1",
                    "visitor.expected",
                ])
        }
    }

    @Test("A whisper reaches its bird alone, through every lookup a mind has (#261)")
    func whispersStayWithTheirBird() async throws {
        let world = MCPWorld()
        let april = try EntityID(validating: "person:april")
        let at = Date(timeIntervalSince1970: 1_789_500_000)
        let house = try ConversationID(validating: "conversation:april-house")
        func item(_ n: Int, _ text: String, by author: EntityID, alone: EntityID?) throws
            -> ConversationItem
        {
            let person = author == april
            return try ConversationItem(
                itemID: ConversationItemID(validating: "conversation-item:whisper-\(n)"),
                conversationID: house, authorID: author,
                authorKind: person ? .person : .character, text: text,
                createdAt: at.addingTimeInterval(Double(n)),
                utteranceID: person ? UtteranceID(validating: "utterance:whisper-\(n)") : nil,
                responseID: person ? nil : ResponseID(validating: "response:whisper-\(n)"),
                aloneWith: alone)
        }
        let items = [
            try item(1, "Goodnight, flock", by: april, alone: nil),
            try item(2, "@beaky just between us", by: april, alone: beaky),
            try item(3, "Just between us, April.", by: beaky, alone: beaky),
        ]
        await world.set(
            day: DayDigest(
                day: "2026-10-22", timeZone: "America/Los_Angeles", happenings: [],
                conversation: items.map {
                    DayDigest.Line(
                        at: $0.createdAt, who: $0.authorID.rawValue, text: $0.text,
                        aloneWith: $0.aloneWith)
                }, scenes: [], learned: []))
        // What a mind was handed: Beaky's percept holds the whisper and her whole page.
        let percept = try WorldEventEnvelope(
            type: PersonUtterancePercept.eventType, occurredAt: at,
            source: EventSource(id: SourceID(validating: "communicator:test"), kind: "person"),
            subjectIDs: [april, beaky], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["utterance": .object(["text": .string("@beaky just between us")])])
        let offer = try WorldEventEnvelope(
            type: SceneTurnOffer.eventType, occurredAt: at,
            source: EventSource(id: SourceID(validating: "world:scenes"), kind: "world"),
            subjectIDs: [april, beaky], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["world_facts": .array([])])
        let arrived = try WorldEventEnvelope(
            type: WorldEventType(validating: "person.arrived"), occurredAt: at,
            source: EventSource(id: SourceID(validating: "home-assistant:test"), kind: "house"),
            subjectIDs: [april], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:])
        let kept = try Fact(
            subjectID: april, predicate: "person.mood", value: .string("tired"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: at,
            derivedFrom: [.event(percept.eventID)],
            producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        // Learned in the whisper: Beaky's alone, fact and event (#263).
        let learnedAlone = try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType, occurredAt: at,
            source: EventSource(id: SourceID(validating: "mind:beaky"), kind: "mind"),
            subjectIDs: [april], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: [
                "subject_id": .string(april.rawValue), "predicate": .string("work.week"),
                "value": .string("long"),
                GivenFactAnnouncement.aloneWithKey: .string(beaky.rawValue),
            ])
        let keptAlone = try Fact(
            subjectID: april, predicate: "work.week", value: .string("long"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: at,
            derivedFrom: [.event(learnedAlone.eventID)],
            producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"),
            aloneWith: beaky)
        await world.set(
            facts: [kept, keptAlone], events: [percept, offer, arrived, learnedAlone])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "whisper-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "whisper-test", schemaVersion: 1),
                worldService: world,
                conversationService: HeldConversation(items: items),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)
        try await application.test(.router) { client in
            func call(_ tool: String, _ arguments: String, meta: String?) async throws
                -> WorldJSONValue?
            {
                let params =
                    #"{"name":"\#(tool)","arguments":\#(arguments)"#
                    + (meta.map { #","_meta":\#($0)}"# } ?? "}")
                let response = try await client.execute(
                    uri: "/world/mcp", method: .post,
                    headers: [.contentType: "application/json", .accept: "application/json"],
                    body: ByteBuffer(
                        string: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"#
                            + params + "}"))
                return try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: response.body)
            }
            func asMind(_ mind: String?) -> String {
                mind.map { #"{"audience":"minds","mind":"\#($0)"}"# } ?? #"{"audience":"minds"}"#
            }
            func texts(_ value: WorldJSONValue?) -> [String] {
                guard case .array(let lines)? = value else { return [] }
                return lines.compactMap { $0["text"]?.stringValue }
            }
            func types(_ value: WorldJSONValue?) -> [String] {
                guard case .array(let events)? = value else { return [] }
                return events.compactMap { $0["type"]?.stringValue }
            }
            let room = ["Goodnight, flock"]
            let all = items.map(\.text)

            // The conversation: the room and her own whispers for Beaky; the room for Mango and
            // for a mind that does not say which it is; everything for April debugging.
            for (meta, heard) in [
                (asMind("character:beaky"), all), (asMind("character:mango"), room),
                (asMind(nil), room), (nil, all),
            ] {
                let conversation = try await call("query_conversation", "{}", meta: meta)
                #expect(texts(conversation?["result"]?["structuredContent"]?["items"]) == heard)
            }
            // The day the night remembers: the same.
            let day = #"{"day":"2026-10-22"}"#
            let mangosDay = try await call("query_day", day, meta: asMind("character:mango"))
            #expect(
                texts(mangosDay?["result"]?["structuredContent"]?["conversation"]) == room)
            let beakysDay = try await call("query_day", day, meta: asMind("character:beaky"))
            #expect(texts(beakysDay?["result"]?["structuredContent"]?["conversation"]) == all)
            // What another mind was handed is no mind's to read, by any tool.
            let entity = try await call(
                "query_entity", #"{"entity_id":"person:april"}"#, meta: asMind("character:mango"))
            #expect(types(entity?["result"]?["structuredContent"]?["events"]) == ["person.arrived"])
            func predicates(_ value: WorldJSONValue?) -> [String] {
                guard case .array(let facts)? = value else { return [] }
                return facts.compactMap { $0["predicate"]?.stringValue }.sorted()
            }
            // What Beaky learned in the whisper is hers: not Mango's, nor an unnamed mind's.
            #expect(
                predicates(entity?["result"]?["structuredContent"]?["facts"]) == ["person.mood"])
            let beakys = try await call(
                "query_entity", #"{"entity_id":"person:april"}"#, meta: asMind("character:beaky"))
            #expect(
                predicates(beakys?["result"]?["structuredContent"]?["facts"]) == [
                    "person.mood", "work.week",
                ])
            #expect(
                types(beakys?["result"]?["structuredContent"]?["events"]) == [
                    "person.arrived", "facts.given",
                ])
            let timeline = try await call(
                "query_timeline", #"{"after_sequence":0}"#, meta: asMind("character:mango"))
            #expect(
                types(timeline?["result"]?["structuredContent"]?["items"]) == ["person.arrived"])
            let why = try await call(
                "explain_fact", #"{"fact_id":"\#(kept.factID.rawValue)"}"#,
                meta: asMind("character:mango"))
            #expect(types(why?["result"]?["structuredContent"]?["events"]) == [])
            let debugging = try await call(
                "query_entity", #"{"entity_id":"person:april"}"#, meta: nil)
            #expect(types(debugging?["result"]?["structuredContent"]?["events"]).count == 4)

            // Over REST, a bird asks for its own day; without `mind` it is whole.
            try await client.execute(
                uri: "/world/v1/days/2026-10-22?mind=character:mango", method: .get
            ) { response in
                #expect(response.status == .ok)
                let digest = try WorldJSON.makeDecoder().decode(DayDigest.self, from: response.body)
                #expect(digest.conversation.map(\.text) == room)
            }
            try await client.execute(uri: "/world/v1/days/2026-10-22", method: .get) { response in
                let digest = try WorldJSON.makeDecoder().decode(DayDigest.self, from: response.body)
                #expect(digest.conversation.map(\.text) == all)
                #expect(digest.conversation.map(\.aloneWith) == [nil, beaky, beaky])
            }
            try await client.execute(
                uri: "/world/v1/days/2026-10-22?mind=not%20a%20mind", method: .get
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("Why? over REST: the same walk, for the Viewer")
    func explainsOverREST() async throws {
        let world = MCPWorld()
        let event = try WorldEventEnvelope(
            eventID: EventID(validating: "00000000-0000-0000-0000-000000000002"),
            type: WorldEventType(validating: "facts.given"),
            occurredAt: Date(timeIntervalSince1970: 1_789_500_000),
            source: EventSource(id: SourceID(validating: "bridge:mail"), kind: "bridge"),
            subjectIDs: [house], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["predicate": .string("visitor.expected")])
        let fact = try Fact(
            subjectID: house, predicate: "visitor.expected",
            value: .string("Quality Cleaning, Etc, Wednesday"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_500_000),
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(kind: "bridge", id: "mail", version: "1"))
        await world.set(facts: [fact], events: [event])
        let application = makeCreatureWorldApplication(
            dependencies: .testing(
                configuration: try CreatureWorldConfiguration(port: 8080),
                logger: Logger(label: "explain-tests"),
                buildInfo: CreatureWorldBuildInfo(version: "explain-test", schemaVersion: 1),
                worldService: world,
                conversationService: UnavailableConversationApplicationService(),
                characterSessionService: UnavailableCharacterSessionApplicationService()),
            apiConfiguration: .default)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/facts/\(fact.factID.rawValue)/explain", method: .get
            ) { response in
                #expect(response.status == .ok)
                let explanation = try WorldJSON.makeDecoder().decode(
                    FactExplanation.self, from: response.body)
                #expect(explanation.fact.factID == fact.factID)
                #expect(explanation.events.map(\.eventID) == [event.eventID])
            }
            try await client.execute(
                uri: "/world/v1/facts/\(FactID.generated().rawValue)/explain", method: .get
            ) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/world/v1/facts/not-a-fact/explain", method: .get) {
                response in
                #expect(response.status == .badRequest)
            }
            // Search over REST, for the Viewer and curl.
            try await client.execute(uri: "/world/v1/search?q=cleaning&limit=5", method: .get) {
                response in
                #expect(response.status == .ok)
                let page = try WorldJSON.makeDecoder().decode(
                    WorldSearchPage.self, from: response.body)
                #expect(page.query == "cleaning")
                #expect(page.hits.map(\.entityID) == [house])
            }
            try await client.execute(uri: "/world/v1/search", method: .get) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("Resource templates match by segment and hand the names over decoded")
    func templatesMatch() {
        #expect(
            WorldMCP.match(
                "world://characters/character%3Abeaky/perspective",
                against: "world://characters/{character_id}/perspective")
                == ["character_id": "character:beaky"])
        #expect(WorldMCP.match("world://timers", against: "world://timers") == [:])
        #expect(WorldMCP.match("world://timers/1", against: "world://timers") == nil)
        #expect(WorldMCP.match("world://entities/", against: "world://entities/{entity_id}") == nil)
    }
}

/// A world with a few facts and events, answering the read-only services WorldMCP uses.
private actor MCPWorld: WorldApplicationService {
    private var facts: [Fact] = []
    private var events: [WorldEventEnvelope] = []
    private var day: DayDigest?

    func set(facts: [Fact], events: [WorldEventEnvelope]) {
        self.facts = facts
        self.events = events
    }

    func set(day: DayDigest) { self.day = day }
    func dayDigest(_ day: String) async throws -> DayDigest? {
        self.day?.day == day ? self.day : nil
    }

    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        throw WorldAPIError.databaseUnavailable
    }
    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        WorldEventPage(events: events, nextSequence: Int64(events.count), hasMore: false)
    }
    func currentFacts(
        subjectID: EntityID?, predicatePrefix: String?, after: FactID?, limit: Int
    ) async throws -> WorldFactPage {
        let matching = facts.filter { fact in
            (subjectID.map { fact.subjectID == $0 } ?? true)
                && (predicatePrefix.map { fact.predicate.hasPrefix($0) } ?? true)
        }
        return WorldFactPage(facts: matching, nextFactID: nil, hasMore: false)
    }
    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        WorldTimerPage(timers: [], nextTimerID: nil, hasMore: false)
    }
    func snapshot(limit: Int) async throws -> WorldSnapshot {
        WorldSnapshot(
            latestSequence: Int64(events.count), facts: facts, timers: [], factsTruncated: false,
            timersTruncated: false)
    }
    func subscribe() async throws -> WorldDeltaStream { throw WorldAPIError.databaseUnavailable }
    func finishSubscriptions() async {}
    private var worldOnly: Set<String> = []
    func set(worldOnly: Set<String>) { self.worldOnly = worldOnly }
    func factKinds() async throws -> FactKindPage {
        FactKindPage(
            kinds: worldOnly.sorted().map {
                FactKind(
                    predicate: $0, meaning: "for the world alone", audience: .world,
                    updatedAt: Date(timeIntervalSince1970: 0), updatedBy: "test")
            })
    }
    func entity(_ entityID: EntityID) async throws -> EntityPage {
        EntityPage(
            entityID: entityID, facts: facts.filter { $0.subjectID == entityID }, linkedFrom: [],
            events: events.filter { $0.subjectIDs.contains(entityID) })
    }
    func perspective(of characterID: EntityID, mentionedIn text: String?) async throws
        -> CharacterPerspective
    {
        CharacterPerspective(
            characterID: characterID, facts: facts, factMeanings: [:], recentHappenings: [])
    }
    func entity(named name: String) async throws -> EntityID? {
        try await search(name, limit: 1).hits.first?.entityID
    }
    func search(_ query: String, limit: Int) async throws -> WorldSearchPage {
        let word = query.lowercased()
        let matching = facts.filter { fact in
            fact.subjectID.rawValue.contains(word)
                || (fact.value.stringValue?.lowercased().contains(word) ?? false)
        }
        let grouped = Dictionary(grouping: matching, by: \.subjectID)
        return WorldSearchPage(
            query: query,
            hits: grouped.map { WorldSearchHit(entityID: $0.key, score: 1, facts: $0.value) }
                .prefix(limit).map { $0 })
    }
    func explain(factID: FactID) async throws -> FactExplanation? {
        guard let fact = facts.first(where: { $0.factID == factID }) else { return nil }
        let behind = fact.derivedFrom.compactMap { reference -> WorldEventEnvelope? in
            if case .event(let id) = reference { return events.first { $0.eventID == id } }
            return nil
        }
        return FactExplanation(fact: fact, events: behind, facts: [], supersededBy: nil)
    }
}

/// The house conversation, held: the only thing these tests ask of the conversation service.
private struct HeldConversation: ConversationApplicationService {
    let items: [ConversationItem]

    func conversationItems(
        in conversationID: ConversationID, after itemID: ConversationItemID?, limit: Int
    ) async throws -> ConversationItemPage {
        let after = itemID.flatMap { id in items.firstIndex { $0.itemID == id } }
        let rest = items.dropFirst(after.map { $0 + 1 } ?? 0).prefix(limit)
        return ConversationItemPage(
            items: Array(rest), nextItemID: rest.last?.itemID,
            hasMore: rest.count < items.count - (after.map { $0 + 1 } ?? 0))
    }

    private var unavailable: UnavailableConversationApplicationService { .init() }
    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        try await unavailable.ingest(utterance)
    }
    func respond(_ intent: CharacterUtteranceIntent) async throws -> CharacterDeliveryResult {
        try await unavailable.respond(intent)
    }
    func stage(_ request: CharacterStageRequest, in conversationID: ConversationID)
        async throws -> CharacterStageResult
    {
        try await unavailable.stage(request, in: conversationID)
    }
    func perform(_ performance: CharacterPerformance, in conversationID: ConversationID)
        async throws -> CharacterDeliveryResult
    {
        try await unavailable.perform(performance, in: conversationID)
    }
    func deliveries(in conversationID: ConversationID, after responseID: ResponseID?, limit: Int)
        async throws -> CharacterDeliveryPage
    {
        try await unavailable.deliveries(in: conversationID, after: responseID, limit: limit)
    }
    func subscribe(to conversationID: ConversationID) async throws -> ConversationItemStream {
        try await unavailable.subscribe(to: conversationID)
    }
    func finishConversationSubscriptions() async {}
}

extension WorldJSONValue {
    fileprivate subscript(key: String) -> WorldJSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }
    fileprivate var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
    fileprivate var arrayCount: Int? {
        if case .array(let items) = self { return items.count }
        return nil
    }
}
