import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import Testing
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

    func set(facts: [Fact], events: [WorldEventEnvelope]) {
        self.facts = facts
        self.events = events
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
    func factKinds() async throws -> FactKindPage { FactKindPage(kinds: []) }
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
