import Foundation
import WorldCore

/// WorldMCP: the world for Codex, Claude, and anyone debugging - the Model Context Protocol over
/// stateless Streamable HTTP, one endpoint, read only. It wraps the same application services
/// the REST API and the Viewer use, never the repositories; MCP's JSON-RPC lives here and
/// nowhere in `WorldCore`. Plan: `docs/beakys-world.md` §4.13.
struct WorldMCP: Sendable {
    static let protocolVersion = "2025-06-18"
    static let serverName = "creature-world"

    let service: any WorldApplicationService
    let conversationService: any ConversationApplicationService
    let sceneService: any SceneApplicationService
    let version: String
    let houseConversation: ConversationID

    // MARK: - JSON-RPC

    struct Request: Decodable {
        var jsonrpc: String
        var id: WorldJSONValue?
        var method: String
        var params: WorldJSONValue?
    }

    enum Failure: Error {
        case invalidParams(String)
        case methodNotFound(String)
        case notFound(String)

        var code: Int {
            switch self {
            case .invalidParams: -32602
            case .methodNotFound: -32601
            case .notFound: -32002
            }
        }

        var message: String {
            switch self {
            case .invalidParams(let why): why
            case .methodNotFound(let method): "unknown method: \(method)"
            case .notFound(let what): "not found: \(what)"
            }
        }
    }

    /// One JSON-RPC message in, one out; nil out for a notification (HTTP 202, no body).
    func handle(_ body: Data) async -> Data? {
        let request: Request
        do {
            request = try WorldJSON.makeDecoder().decode(Request.self, from: body)
        } catch let parseError {
            return encode(
                failure(
                    id: nil, code: -32700, message: "could not parse the request: \(parseError)"))
        }
        guard request.jsonrpc == "2.0" else {
            return encode(failure(id: request.id, code: -32600, message: "jsonrpc must be \"2.0\""))
        }
        if request.method.hasPrefix("notifications/") { return nil }
        do {
            let result = try await dispatch(request.method, params: request.params ?? .object([:]))
            return encode(
                .object(["jsonrpc": .string("2.0"), "id": request.id ?? .null, "result": result]))
        } catch let known as Failure {
            return encode(failure(id: request.id, code: known.code, message: known.message))
        } catch let other {
            return encode(failure(id: request.id, code: -32603, message: "\(other)"))
        }
    }

    private func failure(id: WorldJSONValue?, code: Int, message: String) -> WorldJSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": id ?? .null,
            "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ])
    }

    private func encode(_ value: WorldJSONValue) -> Data {
        (try? WorldJSON.makeEncoder().encode(value)) ?? Data("{}".utf8)
    }

    private func dispatch(_ method: String, params: WorldJSONValue) async throws -> WorldJSONValue {
        switch method {
        case "initialize":
            return .object([
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)]),
                    "resources": .object(["subscribe": .bool(false), "listChanged": .bool(false)]),
                ]),
                "serverInfo": .object([
                    "name": .string(Self.serverName), "version": .string(version),
                    "title": .string("Creature World"),
                ]),
                "instructions": .string(
                    "Beaky's Virtual World, read only. Facts are what the world knows now; events are what happened; a character's perspective is exactly what its mind is handed. Entity ids look like person:april, character:beaky, place:driveway, house:aprils-nest, order:amazon-123, thing:information-bridge."
                ),
            ])
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": .array(Self.tools.map(\.listing))])
        case "tools/call":
            return try await callTool(params)
        case "resources/list":
            return .object(["resources": .array(Self.resources.map(\.listing))])
        case "resources/templates/list":
            return .object(["resourceTemplates": .array(Self.resourceTemplates.map(\.listing))])
        case "resources/read":
            return try await readResource(params)
        default:
            throw Failure.methodNotFound(method)
        }
    }

    // MARK: - Tools

    struct Tool: Sendable {
        var name: String
        var description: String
        var properties: [String: WorldJSONValue]
        var required: [String]

        var listing: WorldJSONValue {
            .object([
                "name": .string(name),
                "description": .string(description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(WorldJSONValue.string)),
                ]),
            ])
        }
    }

    private static func string(_ description: String) -> WorldJSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func integer(_ description: String) -> WorldJSONValue {
        .object(["type": .string("integer"), "description": .string(description)])
    }

    static let tools: [Tool] = [
        Tool(
            name: "search_world",
            description:
                "Find anything by a word or two - a name, a thing, a place, an order, a phrase from a memory. Searches every current fact (subjects, predicates, values) and returns entities best first, each with the facts that matched. Start here when you do not know an entity's id.",
            properties: [
                "query": string(
                    "Words to search for, e.g. \"Tamara\", \"cleaner\", \"toothpaste\"."),
                "limit": integer("At most this many entities (default 10, max 50)."),
            ], required: ["query"]),
        Tool(
            name: "inspect_world_state",
            description:
                "Current facts, newest first: everything, or one subject, or one predicate prefix (e.g. \"visitor.\", \"body.\"). Each fact carries its epistemic basis, validity window, and provenance.",
            properties: [
                "subject_id": string(
                    "An entity id (person:tamara, place:front-door, house:aprils-nest) or a name the world knows (\"Tamara\", \"my mom\")."
                ),
                "predicate_prefix": string("A predicate or prefix, e.g. order. or presence.state."),
                "limit": integer("At most this many facts (default 100, max 500)."),
            ], required: []),
        Tool(
            name: "query_entity",
            description:
                "One entity, whole: its current facts (every audience), the facts elsewhere that point at it, and recent events about it.",
            properties: [
                "entity_id": string(
                    "An entity id (person:tamara, character:mango, thing:hopper) or a name the world knows."
                )
            ], required: ["entity_id"]),
        Tool(
            name: "explain_fact",
            description:
                "Why a fact is what it is: the fact, the events and facts it was derived from (a few levels), and what superseded it. Give a fact_id, or a subject_id and predicate for the current fact.",
            properties: [
                "fact_id": string("A fact id."),
                "subject_id": string("With predicate: the subject of the current fact to explain."),
                "predicate": string("With subject_id: the predicate."),
            ], required: []),
        Tool(
            name: "query_timeline",
            description:
                "Events from the world's log in order. Newest first by default (the last `limit`); or after a sequence number. Filter by event type prefix or subject.",
            properties: [
                "after_sequence": integer("Read forward from this sequence; omit for the newest."),
                "limit": integer("At most this many events (default 50, max 500)."),
                "type_prefix": string(
                    "Keep only events whose type starts with this, e.g. camera., scene., facts.given."
                ),
                "subject_id": string("Keep only events with this subject."),
            ], required: []),
        Tool(
            name: "query_character_perspective",
            description:
                "Exactly what a character's mind would be handed right now: the facts about it, its region, and April (plus mentions in `mentioned_in`), the meanings of those kinds, and the recent story.",
            properties: [
                "character_id": string("e.g. character:beaky."),
                "mentioned_in": string(
                    "Words to resolve mentions in, as April's question would - e.g. \"did I order a DJI mic?\"."
                ),
            ], required: ["character_id"]),
        Tool(
            name: "query_scenes",
            description:
                "The most recent scenes: trigger, participants, every turn (spoken or quiet, with the reason), performance.",
            properties: ["limit": integer("At most this many (default 5, max 50).")], required: []),
        Tool(
            name: "query_conversation",
            description: "The newest items of a conversation (default the house's), oldest first.",
            properties: [
                "conversation_id": string("Default conversation:april-house."),
                "limit": integer("At most this many, from the end (default 50, max 500)."),
            ], required: []),
        Tool(
            name: "query_timers",
            description: "Durable world timers: scheduled, fired, cancelled.",
            properties: [
                "status": string("scheduled, fired, or cancelled; omit for all."),
                "limit": integer("At most this many (default 50)."),
            ], required: []),
        Tool(
            name: "query_day",
            description:
                "One day's record as the nightly memory sees it: happenings, conversation, scenes, learned facts.",
            properties: ["day": string("YYYY-MM-DD in the house's time zone.")], required: ["day"]),
        Tool(
            name: "query_glossary",
            description:
                "What every kind of fact means to the minds, with its audience (minds or world) and who last reworded it.",
            properties: [:], required: []),
    ]

    /// Who is asking. A mind says so (`params._meta.audience = "minds"`), and then a fact the
    /// glossary keeps for the world alone - a phone number, a street - never reaches it: the
    /// envelope has always honoured `audience`, and a tool must not be the way around it.
    /// Beaky once read Polly's mobile number aloud in the room. A person debugging asks
    /// without `_meta` and sees everything.
    private func audience(of params: WorldJSONValue) -> FactAudience? {
        guard case .string(let raw)? = params["_meta"]?["audience"] else { return nil }
        return FactAudience(rawValue: raw)
    }

    /// The facts a caller may see: all of them, or the minds' alone.
    private func visible(_ facts: [Fact], to audience: FactAudience?) async throws -> [Fact] {
        guard audience == .minds else { return facts }
        let hidden = Set(
            try await service.factKinds().kinds.filter { $0.audience == .world }.map(\.predicate))
        return facts.filter { !hidden.contains($0.predicate) }
    }

    private func callTool(_ params: WorldJSONValue) async throws -> WorldJSONValue {
        guard case .string(let name)? = params["name"] else {
            throw Failure.invalidParams("tools/call needs a name")
        }
        let arguments = params["arguments"] ?? .object([:])
        let audience = audience(of: params)
        let result: any Encodable & Sendable
        switch name {
        case "inspect_world_state":
            let page = try await service.currentFacts(
                subjectID: try await entityID(arguments["subject_id"]),
                predicatePrefix: arguments["predicate_prefix"].flatMap(\.stringValue),
                after: nil, limit: limit(arguments["limit"], default: 100, max: 500))
            result = try await visible(page.facts, to: audience)
        case "search_world":
            guard case .string(let query)? = arguments["query"],
                !query.trimmingCharacters(in: .whitespaces).isEmpty
            else { throw Failure.invalidParams("query is required") }
            var page = try await service.search(
                query,
                limit: limit(
                    arguments["limit"], default: WorldSearchLimits.defaultHits,
                    max: WorldSearchLimits.maximumHits))
            if audience == .minds {
                var kept: [WorldSearchHit] = []
                for var hit in page.hits {
                    hit.facts = try await visible(hit.facts, to: audience)
                    if !hit.facts.isEmpty { kept.append(hit) }
                }
                page.hits = kept
            }
            result = page
        case "query_entity":
            guard let id = try await entityID(arguments["entity_id"]) else {
                throw Failure.invalidParams("entity_id is required")
            }
            var page = try await service.entity(id)
            page.facts = try await visible(page.facts, to: audience)
            page.linkedFrom = try await visible(page.linkedFrom, to: audience)
            result = page
        case "explain_fact":
            let factID: FactID
            if case .string(let raw)? = arguments["fact_id"] {
                factID = try FactID(validating: raw)
            } else if let subject = try await entityID(arguments["subject_id"]),
                case .string(let predicate)? = arguments["predicate"]
            {
                let page = try await service.currentFacts(
                    subjectID: subject, predicatePrefix: predicate, after: nil, limit: 50)
                guard let fact = page.facts.first(where: { $0.predicate == predicate }) else {
                    throw Failure.notFound("no current fact \(predicate) on \(subject.rawValue)")
                }
                factID = fact.factID
            } else {
                throw Failure.invalidParams("give fact_id, or subject_id and predicate")
            }
            guard var explanation = try await service.explain(factID: factID) else {
                throw Failure.notFound(factID.rawValue)
            }
            if audience == .minds {
                // A world-only fact has no why for a mind; the facts behind one are trimmed.
                guard try await !visible([explanation.fact], to: audience).isEmpty else {
                    throw Failure.notFound(factID.rawValue)
                }
                explanation.facts = try await visible(explanation.facts, to: audience)
                if let successor = explanation.supersededBy {
                    explanation.supersededBy = try await visible([successor], to: audience).first
                }
            }
            result = explanation
        case "query_timeline":
            result = try await timeline(arguments)
        case "query_character_perspective":
            guard let id = try await entityID(arguments["character_id"]) else {
                throw Failure.invalidParams("character_id is required")
            }
            result = try await service.perspective(
                of: id, mentionedIn: arguments["mentioned_in"].flatMap(\.stringValue))
        case "query_scenes":
            result = try await sceneService.recentScenes(
                limit: limit(arguments["limit"], default: 5, max: 50))
        case "query_conversation":
            result = try await conversation(arguments)
        case "query_timers":
            let status = try arguments["status"].flatMap(\.stringValue).map { raw in
                guard let status = WorldTimerStatus(rawValue: raw) else {
                    throw Failure.invalidParams("status must be scheduled, fired, or cancelled")
                }
                return status
            }
            result = try await service.timers(
                status: status, after: nil, limit: limit(arguments["limit"], default: 50, max: 500)
            ).timers
        case "query_day":
            guard case .string(let day)? = arguments["day"] else {
                throw Failure.invalidParams("day is required")
            }
            guard let digest = try await service.dayDigest(day) else {
                throw Failure.notFound("no record of \(day)")
            }
            result = digest
        case "query_glossary":
            result = try await service.factKinds().kinds
        default:
            throw Failure.methodNotFound("tool \(name)")
        }
        return try toolResult(result)
    }

    func timeline(_ arguments: WorldJSONValue) async throws -> [WorldEventEnvelope] {
        let wanted = limit(arguments["limit"], default: 50, max: 500)
        let typePrefix = arguments["type_prefix"].flatMap(\.stringValue)
        let subject = try await entityID(arguments["subject_id"])
        func keep(_ event: WorldEventEnvelope) -> Bool {
            (typePrefix.map { event.type.rawValue.hasPrefix($0) } ?? true)
                && (subject.map { event.subjectIDs.contains($0) } ?? true)
        }
        if case .number(let after)? = arguments["after_sequence"] {
            let page = try await service.events(after: Int64(after), limit: 500)
            return Array(page.events.filter(keep).prefix(wanted))
        }
        // Newest: walk back from the end in pages until enough are kept, or the log runs out.
        let latest = try await service.snapshot(limit: 1).latestSequence
        var kept: [WorldEventEnvelope] = []
        var end = latest
        for _ in 0..<8 where kept.count < wanted && end > 0 {
            let start = max(0, end - 500)
            let page = try await service.events(after: start, limit: 500)
            kept = page.events.filter(keep) + kept
            end = start
        }
        return Array(kept.suffix(wanted))
    }

    private func conversation(_ arguments: WorldJSONValue) async throws -> [ConversationItem] {
        let conversationID =
            try arguments["conversation_id"].flatMap(\.stringValue).map {
                try ConversationID(validating: $0)
            } ?? houseConversation
        let wanted = limit(arguments["limit"], default: 50, max: 500)
        // Oldest first, a page at a time, to the end; keep the newest.
        var items: [ConversationItem] = []
        var after: ConversationItemID?
        for _ in 0..<40 {
            let page = try await conversationService.conversationItems(
                in: conversationID, after: after, limit: 500)
            items = Array((items + page.items).suffix(wanted))
            guard page.hasMore, let last = page.items.last else { break }
            after = last.itemID
        }
        return items
    }

    private func toolResult(_ value: any Encodable & Sendable) throws -> WorldJSONValue {
        let data = try WorldJSON.makeEncoder().encode(value)
        let structured = try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: data)
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"), "text": .string(String(decoding: data, as: UTF8.self)),
                ])
            ]),
            "structuredContent": structured.isObject ? structured : .object(["items": structured]),
        ])
    }

    // MARK: - Resources

    struct Resource: Sendable {
        var uri: String
        var name: String
        var description: String

        var listing: WorldJSONValue {
            .object([
                "uri": .string(uri), "name": .string(name), "description": .string(description),
                "mimeType": .string("application/json"),
            ])
        }
    }

    struct ResourceTemplate: Sendable {
        var uriTemplate: String
        var name: String
        var description: String

        var listing: WorldJSONValue {
            .object([
                "uriTemplate": .string(uriTemplate), "name": .string(name),
                "description": .string(description), "mimeType": .string("application/json"),
            ])
        }
    }

    static let resources: [Resource] = [
        Resource(
            uri: "world://events/recent", name: "Recent events",
            description: "The newest 100 events."),
        Resource(uri: "world://timers", name: "Timers", description: "Durable world timers."),
        Resource(
            uri: "world://scenes/recent", name: "Recent scenes",
            description: "The newest 10 scenes."),
        Resource(
            uri: "world://glossary", name: "Glossary", description: "What each kind of fact means."),
    ]

    static let resourceTemplates: [ResourceTemplate] = [
        ResourceTemplate(
            uriTemplate: "world://entities/{entity_id}", name: "Entity",
            description: "One entity, whole."),
        ResourceTemplate(
            uriTemplate: "world://characters/{character_id}/perspective", name: "Perspective",
            description: "What a character's mind is handed right now."),
        ResourceTemplate(
            uriTemplate: "world://characters/{character_id}/memories", name: "Memories",
            description: "A character's memories, newest first."),
        ResourceTemplate(
            uriTemplate: "world://provenance/{fact_id}", name: "Provenance",
            description: "Why a fact is what it is."),
    ]


    private func readResource(_ params: WorldJSONValue) async throws -> WorldJSONValue {
        guard case .string(let uri)? = params["uri"] else {
            throw Failure.invalidParams("resources/read needs a uri")
        }
        guard
            let (template, fill) = Self.resourceRoutes.lazy.compactMap({ route in
                Self.match(uri, against: route.template).map { (route, $0) }
            }).first
        else {
            throw Failure.notFound(uri)
        }
        let value = try await template.read(self, fill)
        let data = try WorldJSON.makeEncoder().encode(value)
        return .object([
            "contents": .array([
                .object([
                    "uri": .string(uri), "mimeType": .string("application/json"),
                    "text": .string(String(decoding: data, as: UTF8.self)),
                ])
            ])
        ])
    }

    /// One resource: a `world://` template and how to read it, the template's `{name}`
    /// segments handed over by name.
    struct ResourceRoute: Sendable {
        var template: String
        var read: @Sendable (WorldMCP, [String: String]) async throws -> any Encodable & Sendable
    }

    static let resourceRoutes: [ResourceRoute] = [
        ResourceRoute(template: "world://events/recent") { mcp, _ in
            try await mcp.timeline(.object(["limit": .number(100)]))
        },
        ResourceRoute(template: "world://timers") { mcp, _ in
            try await mcp.service.timers(status: nil, after: nil, limit: 100).timers
        },
        ResourceRoute(template: "world://scenes/recent") { mcp, _ in
            try await mcp.sceneService.recentScenes(limit: 10)
        },
        ResourceRoute(template: "world://glossary") { mcp, _ in
            try await mcp.service.factKinds().kinds
        },
        ResourceRoute(template: "world://entities/{entity_id}") { mcp, fill in
            try await mcp.service.entity(try EntityID(validating: fill["entity_id"]!))
        },
        ResourceRoute(template: "world://characters/{character_id}/perspective") { mcp, fill in
            try await mcp.service.perspective(
                of: try EntityID(validating: fill["character_id"]!), mentionedIn: nil)
        },
        ResourceRoute(template: "world://characters/{character_id}/memories") { mcp, fill in
            try await mcp.service.currentFacts(
                subjectID: try EntityID(validating: fill["character_id"]!),
                predicatePrefix: "memory.", after: nil, limit: 200
            ).facts
        },
        ResourceRoute(template: "world://provenance/{fact_id}") { mcp, fill in
            guard
                let explanation = try await mcp.service.explain(
                    factID: try FactID(validating: fill["fact_id"]!))
            else { throw Failure.notFound(fill["fact_id"]!) }
            return explanation
        },
    ]

    /// "world://characters/character:beaky/perspective" against
    /// "world://characters/{character_id}/perspective" → ["character_id": "character:beaky"];
    /// nil when the shape differs. Segments are percent-decoded.
    static func match(_ uri: String, against template: String) -> [String: String]? {
        let given = uri.split(separator: "/", omittingEmptySubsequences: false)
        let wanted = template.split(separator: "/", omittingEmptySubsequences: false)
        guard given.count == wanted.count else { return nil }
        var fill: [String: String] = [:]
        for (segment, pattern) in zip(given, wanted) {
            if pattern.hasPrefix("{"), pattern.hasSuffix("}") {
                let name = String(pattern.dropFirst().dropLast())
                let value = String(segment).removingPercentEncoding ?? String(segment)
                guard !value.isEmpty else { return nil }
                fill[name] = value
            } else if segment != pattern {
                return nil
            }
        }
        return fill
    }

    // MARK: - Arguments

    /// An entity from a tool argument: an id (`person:tamara`), or a name the world knows -
    /// a mind asked "who is Tamara?" and asked the world for "Tamara", which is what it had.
    /// A name nobody answers to is a clear refusal with the shape of an id in it.
    private func entityID(_ value: WorldJSONValue?) async throws -> EntityID? {
        guard case .string(let raw)? = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = try? EntityID(validating: trimmed), trimmed.contains(":") { return id }
        if let known = try await service.entity(named: trimmed) { return known }
        throw Failure.invalidParams(
            "the world knows no entity called \"\(trimmed)\"; ids look like person:tamara, place:front-door, character:beaky - or give a name the world has facts about"
        )
    }

    private func limit(_ value: WorldJSONValue?, default fallback: Int, max cap: Int) -> Int {
        guard case .number(let number)? = value, number > 0 else { return fallback }
        return min(Int(number), cap)
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

    fileprivate var isObject: Bool {
        if case .object = self { return true }
        return false
    }
}
