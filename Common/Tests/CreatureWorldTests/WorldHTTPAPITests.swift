import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import Testing
import WorldCore

@testable import creature_world

@Suite("Creature World HTTP API")
struct WorldHTTPAPITests {
    @Test("Conversation ingress is ordered and idempotent over HTTP")
    func conversationIngressAndHistory() async throws {
        let worldService = TestWorldApplicationService()
        let conversationService = TestConversationApplicationService()
        let application = try makeApplication(
            worldService: worldService,
            conversationService: conversationService
        )
        let utterance = try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:http-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Can you hear me?",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_100_000),
            confidence: 1
        )
        let body = try encode(utterance)
        let traceparents = [
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-11f067aa0ba902b7-01",
        ]

        try await application.test(.router) { client in
            for (expectedStatus, traceparent) in zip(
                [HTTPResponse.Status.accepted, .ok], traceparents
            ) {
                var headers = HTTPFields()
                headers[.contentType] = "application/json"
                headers[HTTPField.Name("traceparent")!] = traceparent
                try await client.execute(
                    uri: "/world/v1/conversations/conversation:april-beaky/utterances",
                    method: .post,
                    headers: headers,
                    body: body
                ) { response in
                    #expect(response.status == expectedStatus)
                    let result = try decode(UtteranceIngressResult.self, response.body)
                    #expect(result.conversationItem.text == utterance.text)
                    // The first attempt's transport trace is carried on the utterance so the
                    // mind can continue April's trace; the retry does not replace it.
                    #expect(result.percept.utterance.trace?.traceparent == traceparents[0])
                }
            }

            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/items?limit=10",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decode(ConversationItemPage.self, response.body)
                #expect(page.items.map(\.utteranceID) == [utterance.utteranceID])
                #expect(page.nextItemID == page.items.last?.itemID)
                #expect(!page.hasMore)
            }
        }
    }

    @Test("Beaky's turn joins the conversation over HTTP exactly once")
    func characterResponseIngressAndHistory() async throws {
        let conversationService = TestConversationApplicationService()
        let application = try makeApplication(
            worldService: TestWorldApplicationService(),
            conversationService: conversationService
        )
        let utterance = try makeUtterance(
            id: "utterance:http-april",
            occurredAt: Date(timeIntervalSince1970: 1_789_100_000)
        )
        let intent = try makeIntent(
            id: "response:http-beaky",
            inResponseTo: utterance.utteranceID,
            createdAt: Date(timeIntervalSince1970: 1_789_100_005)
        )
        let headers: HTTPFields = [.contentType: "application/json"]

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/utterances",
                method: .post,
                headers: headers,
                body: try encode(utterance)
            ) { response in
                #expect(response.status == .accepted)
            }

            for expectedStatus in [HTTPResponse.Status.accepted, .ok] {
                try await client.execute(
                    uri: "/world/v1/conversations/conversation:april-beaky/responses",
                    method: .post,
                    headers: headers,
                    body: try encode(intent)
                ) { response in
                    #expect(response.status == expectedStatus)
                    let result = try decode(CharacterDeliveryResult.self, response.body)
                    #expect(result.conversationItem.authorKind == .character)
                    #expect(result.conversationItem.responseID == intent.responseID)
                    #expect(result.conversationItem.text == intent.text)
                    #expect(result.outcome.route == .communicator)
                    #expect(result.outcome.state == .accepted)
                    #expect(
                        result.disposition
                            == (expectedStatus == .accepted ? .accepted : .duplicate))
                    let json = try #require(
                        JSONSerialization.jsonObject(
                            with: Data(buffer: response.body)) as? [String: Any])
                    #expect(Set(json.keys) == ["disposition", "outcome", "conversation_item"])
                }
            }

            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/items?limit=10",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decode(ConversationItemPage.self, response.body)
                #expect(page.items.map(\.authorKind) == [.person, .character])
                #expect(page.items.last?.responseID == intent.responseID)
            }

            // The Viewer reads what the router decided about each of Beaky's turns.
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/deliveries?limit=10",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decode(CharacterDeliveryPage.self, response.body)
                #expect(page.deliveries.count == 1)
                #expect(page.deliveries.first?.intent.responseID == intent.responseID)
                #expect(page.deliveries.first?.decision.reason == .presenceUncertain)
                #expect(page.deliveries.first?.outcome?.state == .accepted)
                #expect(page.nextResponseID == intent.responseID)
                #expect(!page.hasMore)
                let json = try #require(
                    JSONSerialization.jsonObject(with: Data(buffer: response.body))
                        as? [String: Any])
                #expect(Set(json.keys) == ["deliveries", "next_response_id", "has_more"])
            }
            try await client.execute(
                uri:
                    "/world/v1/conversations/conversation:april-beaky/deliveries?after_response_id=\(intent.responseID.rawValue)",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decode(CharacterDeliveryPage.self, response.body)
                #expect(page.deliveries.isEmpty)
            }
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/deliveries?limit=0",
                method: .get
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("A staged turn is performed by the mind and recorded over HTTP exactly once")
    func stagedPerformanceOverHTTP() async throws {
        let conversationService = TestConversationApplicationService()
        let application = try makeApplication(
            worldService: TestWorldApplicationService(),
            conversationService: conversationService
        )
        let intent = try makeIntent(
            id: "response:http-staged",
            inResponseTo: UtteranceID(validating: "utterance:http-april"),
            createdAt: Date(timeIntervalSince1970: 1_789_100_005)
        )
        let stageRequest = CharacterStageRequest(
            responseID: intent.responseID,
            characterID: intent.characterID,
            recipientID: intent.recipientID
        )
        let headers: HTTPFields = [.contentType: "application/json"]

        try await application.test(.router) { client in
            var attemptID: DeliveryAttemptID?
            for _ in 0..<2 {
                try await client.execute(
                    uri: "/world/v1/conversations/conversation:april-beaky/stage",
                    method: .post,
                    headers: headers,
                    body: try encode(stageRequest)
                ) { response in
                    #expect(response.status == .ok)
                    let stage = try decode(CharacterStageResult.self, response.body)
                    #expect(stage.disposition == .decided)
                    #expect(stage.decision.route == .physicalSpeech)
                    #expect(stage.decision.presence.basis == .assumed)
                    #expect(attemptID == nil || attemptID == stage.decision.attemptID)
                    attemptID = stage.decision.attemptID
                    let json = try #require(
                        JSONSerialization.jsonObject(
                            with: Data(buffer: response.body)) as? [String: Any])
                    #expect(Set(json.keys) == ["disposition", "decision"])
                }
            }

            let performance = try CharacterPerformance(
                intent: intent,
                attemptID: #require(attemptID),
                outcome: CharacterPerformanceReport(
                    state: .performed, providerReference: "animation:42")
            )
            for expectedStatus in [HTTPResponse.Status.accepted, .ok] {
                try await client.execute(
                    uri: "/world/v1/conversations/conversation:april-beaky/performances",
                    method: .post,
                    headers: headers,
                    body: try encode(performance)
                ) { response in
                    #expect(response.status == expectedStatus)
                    let result = try decode(CharacterDeliveryResult.self, response.body)
                    #expect(result.outcome.route == .physicalSpeech)
                    #expect(result.outcome.state == .performed)
                    #expect(result.outcome.providerReference == "animation:42")
                    #expect(result.conversationItem.text == intent.text)
                }
            }

            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/stage",
                method: .post,
                headers: headers,
                body: try encode(stageRequest)
            ) { response in
                #expect(response.status == .ok)
                let stage = try decode(CharacterStageResult.self, response.body)
                #expect(stage.disposition == .alreadyDelivered)
            }

            let unstaged = try CharacterPerformance(
                intent: makeIntent(
                    id: "response:http-unstaged",
                    inResponseTo: UtteranceID(validating: "utterance:http-april"),
                    createdAt: Date(timeIntervalSince1970: 1_789_100_006)),
                attemptID: DeliveryAttemptID(validating: "delivery-attempt:nobody-asked"),
                outcome: CharacterPerformanceReport(state: .performed)
            )
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/performances",
                method: .post,
                headers: headers,
                body: try encode(unstaged)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("A mind logs in as a character over HTTP; a second one is told it is logged in elsewhere")
    func characterLoginOverHTTP() async throws {
        let sessions = CharacterSessionService(
            repository: InMemorySessionRepository(),
            clock: ManualWorldClock(now: Date(timeIntervalSince1970: 1_789_300_000)),
            announce: { _ in }
        )
        let application = try makeApplication(
            worldService: TestWorldApplicationService(),
            characterSessionService: sessions
        )
        let headers: HTTPFields = [.contentType: "application/json"]
        let fuzzball = CharacterLoginRequest(
            regionID: try EntityID(validating: "region:home"),
            instance: CharacterMindInstance(host: "fuzzball", processID: 1))
        let laptop = CharacterLoginRequest(
            regionID: try EntityID(validating: "region:home"),
            instance: CharacterMindInstance(host: "laptop", processID: 2))

        try await application.test(.router) { client in
            var sessionID: CharacterSessionID?
            try await client.execute(
                uri: "/world/v1/characters/character:beaky/login", method: .post,
                headers: headers, body: try encode(fuzzball)
            ) { response in
                #expect(response.status == .ok)
                let result = try decode(CharacterLoginResult.self, response.body)
                #expect(result.disposition == .loggedIn)
                sessionID = result.session.sessionID
            }
            try await client.execute(
                uri: "/world/v1/characters/character:beaky/login", method: .post,
                headers: headers, body: try encode(laptop)
            ) { response in
                #expect(response.status == .conflict)
                let result = try decode(CharacterLoginResult.self, response.body)
                #expect(result.disposition == .loggedInElsewhere)
                #expect(result.session.instance.host == "fuzzball")
            }
            let reference = CharacterSessionReference(sessionID: try #require(sessionID))
            try await client.execute(
                uri: "/world/v1/characters/character:beaky/heartbeat", method: .post,
                headers: headers, body: try encode(reference)
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/world/v1/characters", method: .get) { response in
                #expect(response.status == .ok)
                let page = try decode(CharacterSessionPage.self, response.body)
                #expect(page.sessions.map(\.characterID.rawValue) == ["character:beaky"])
                #expect(page.sessions.first?.state == .active)
            }
            try await client.execute(
                uri: "/world/v1/characters/character:beaky/logout", method: .post,
                headers: headers, body: try encode(reference)
            ) { response in
                #expect(response.status == .ok)
                let ended = try decode(CharacterSession.self, response.body)
                #expect(ended.state == .loggedOut)
            }
        }
    }

    @Test("A Beaky turn addressed to another conversation is refused")
    func characterResponseIdentityMismatchIsRejected() async throws {
        let application = try makeApplication(
            worldService: TestWorldApplicationService(),
            conversationService: TestConversationApplicationService()
        )
        let intent = try makeIntent(
            id: "response:http-mismatch",
            inResponseTo: nil,
            createdAt: Date(timeIntervalSince1970: 1_789_100_005)
        )
        let headers: HTTPFields = [.contentType: "application/json"]

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/conversations/conversation:someone-else/responses",
                method: .post,
                headers: headers,
                body: try encode(intent)
            ) { response in
                #expect(response.status == .conflict)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "conversation_identity_mismatch")
            }
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/responses",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"schema_version":1,"text":"not an intent"}"#)
            ) { response in
                #expect(response.status == .badRequest)
            }
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/responses",
                method: .post,
                body: try encode(intent)
            ) { response in
                #expect(response.status == .unsupportedMediaType)
            }
        }
    }

    @Test("Beaky's turn is unavailable while persistence is down")
    func characterResponseWithoutPersistence() async throws {
        let application = try makeApplication(
            worldService: TestWorldApplicationService(),
            conversationService: UnavailableConversationApplicationService()
        )
        let intent = try makeIntent(
            id: "response:http-unavailable",
            inResponseTo: nil,
            createdAt: Date(timeIntervalSince1970: 1_789_100_005)
        )
        let headers: HTTPFields = [.contentType: "application/json"]

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/responses",
                method: .post,
                headers: headers,
                body: try encode(intent)
            ) { response in
                #expect(response.status == .serviceUnavailable)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "persistence_unavailable")
            }
        }
    }

    @Test("Conversation SSE pushes a newly accepted item")
    func conversationStreamPublishesLiveItem() async throws {
        let conversationService = TestConversationApplicationService()
        let application = try makeApplication(
            worldService: UnavailableWorldApplicationService(),
            conversationService: conversationService
        )
        let utterance = try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:stream-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Wake every connected client",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_100_001),
            confidence: 1
        )

        try await application.test(.router) { client in
            let streamRequest = Task {
                try await client.execute(
                    uri: "/world/v1/conversations/conversation:april-beaky/stream",
                    method: .get
                ) { response in
                    #expect(response.status == .ok)
                    #expect(response.headers[.contentType] == "text/event-stream; charset=utf-8")
                    #expect(response.headers[HTTPField.Name("x-accel-buffering")!] == "no")
                    return String(buffer: response.body)
                }
            }
            while await conversationService.subscriptionCount == 0 {
                await Task.yield()
            }

            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/utterances",
                method: .post,
                headers: [.contentType: "application/json"],
                body: try encode(utterance)
            ) { response in
                #expect(response.status == .accepted)
            }
            await conversationService.finishSubscriptions()
            let body = try await streamRequest.value

            #expect(body.contains("event: ready"))
            #expect(body.contains("event: item"))
            #expect(body.contains("id: conversation-item:utterance:stream-test"))
            #expect(body.contains("Wake every connected client"))
        }
    }

    @Test("Conversation SSE browser origins are allowlisted")
    func conversationStreamOriginValidation() async throws {
        let configuration = try CreatureWorldConfiguration(
            allowedOrigins: ["https://communicator.example"]
        )
        let application = try makeApplication(
            configuration: configuration,
            worldService: UnavailableWorldApplicationService(),
            conversationService: TestConversationApplicationService()
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/conversations/conversation:april-beaky/stream",
                method: .get,
                headers: [.origin: "https://evil.example"]
            ) { response in
                #expect(response.status == .forbidden)
            }
        }
    }

    @Test("Event ingress is ordered, queryable, and idempotent over HTTP")
    func eventIngressAndHistory() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(worldService: service)
        let event = try makeEvent()
        let body = try encode(event)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .accepted)
                let result = try decode(WorldEventAcceptanceResponse.self, response.body)
                #expect(result.disposition == .accepted)
                #expect(result.event.worldSequence == 1)
                #expect(result.event.receivedAt != nil)
            }
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .ok)
                let result = try decode(WorldEventAcceptanceResponse.self, response.body)
                #expect(result.disposition == .duplicateEvent)
                #expect(result.event.worldSequence == 1)
            }
            try await client.execute(
                uri: "/world/v1/events?after_sequence=0&limit=10",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decode(WorldEventPage.self, response.body)
                #expect(page.events.map(\.eventID) == [event.eventID])
                #expect(page.nextSequence == 1)
                #expect(!page.hasMore)
            }
        }
    }

    @Test("Batch ingress is bounded and preserves acceptance order")
    func batchIngress() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(
            worldService: service,
            apiConfiguration: WorldAPIConfiguration(maximumBatchSize: 2)
        )
        let first = try makeEvent(id: "00000000-0000-0000-0000-000000000001")
        let second = try makeEvent(id: "00000000-0000-0000-0000-000000000002")

        try await application.test(.router) { client in
            let acceptedBody = try encode(WorldEventBatchRequest(events: [first, second]))
            try await client.execute(
                uri: "/world/v1/events:batch",
                method: .post,
                headers: [.contentType: "application/json"],
                body: acceptedBody
            ) { response in
                #expect(response.status == .ok)
                let result = try decode(WorldEventBatchResponse.self, response.body)
                #expect(result.results.map(\.event.worldSequence) == [1, 2])
            }

            let oversizedBody = try encode(
                WorldEventBatchRequest(events: [first, second, try makeEvent()])
            )
            try await client.execute(
                uri: "/world/v1/events:batch",
                method: .post,
                headers: [.contentType: "application/json"],
                body: oversizedBody
            ) { response in
                #expect(response.status == .contentTooLarge)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "batch_too_large")
            }
        }
    }

    @Test("Body and pagination limits fail explicitly")
    func requestLimits() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(
            worldService: service,
            apiConfiguration: WorldAPIConfiguration(
                maximumBodyBytes: 64,
                maximumPageSize: 10,
                defaultPageSize: 5
            )
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                body: ByteBuffer(string: "{}")
            ) { response in
                #expect(response.status == .unsupportedMediaType)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "unsupported_media_type")
            }
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: String(repeating: "x", count: 65))
            ) { response in
                #expect(response.status == .contentTooLarge)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "body_too_large")
            }
            try await client.execute(uri: "/world/v1/events?limit=11", method: .get) { response in
                #expect(response.status == .badRequest)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "invalid_query")
            }
        }
    }

    @Test("Non-loopback APIs remain open without credentials")
    func nonLoopbackAccess() async throws {
        let service = TestWorldApplicationService()
        let configuration = try CreatureWorldConfiguration(
            host: "0.0.0.0",
            port: 8080
        )
        let application = try makeApplication(
            configuration: configuration,
            worldService: service
        )

        try await application.test(.router) { client in
            try await client.execute(uri: "/world/v1/health", method: .get) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/world/v1/events", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("Trace context enters the canonical event without logging payload data")
    func traceContextPropagation() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(worldService: service)
        let event = try makeEvent()
        let headers: HTTPFields = {
            var headers = HTTPFields()
            headers[HTTPField.Name("traceparent")!] =
                "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
            return headers
        }()

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: headers.withJSONContentType,
                body: try encode(event)
            ) { response in
                let result = try decode(WorldEventAcceptanceResponse.self, response.body)
                #expect(
                    result.event.trace?.traceparent
                        == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
                )
            }
        }
    }

    @Test("Malformed trace context is rejected before event acceptance")
    func malformedTraceContext() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(worldService: service)
        let headers: HTTPFields = {
            var headers = HTTPFields()
            headers[HTTPField.Name("traceparent")!] = "not-a-traceparent"
            return headers
        }()

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: headers.withJSONContentType,
                body: try encode(makeEvent())
            ) { response in
                #expect(response.status == .badRequest)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "invalid_request")
            }
        }
        #expect(await service.eventCount == 0)
    }

    @Test("SSE reconnect sends ordered history without a gap")
    func streamReconnect() async throws {
        let service = TestWorldApplicationService()
        _ = try await service.accept(try makeEvent(id: "00000000-0000-0000-0000-000000000001"))
        _ = try await service.accept(try makeEvent(id: "00000000-0000-0000-0000-000000000002"))
        await service.finishNewSubscriptionsImmediately()
        let application = try makeApplication(worldService: service)
        let headers: HTTPFields = {
            var headers = HTTPFields()
            headers[HTTPField.Name("last-event-id")!] = "1"
            return headers
        }()

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/stream",
                method: .get,
                headers: headers
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/event-stream; charset=utf-8")
                let body = String(buffer: response.body)
                #expect(body.contains("event: event"))
                #expect(body.contains("id: 2"))
                #expect(!body.contains("id: 1\n"))
            }
        }
    }

    @Test("SSE publishes an accepted event after its initial snapshot")
    func streamPublishesLiveDelta() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(worldService: service)

        try await application.test(.router) { client in
            let streamRequest = Task {
                try await client.execute(uri: "/world/v1/stream", method: .get) { response in
                    #expect(response.status == .ok)
                    return String(buffer: response.body)
                }
            }
            while !(await service.snapshotWasRead) {
                await Task.yield()
            }

            let acceptance = try await service.accept(makeEvent())
            await service.finishSubscriptions()
            let body = try await streamRequest.value

            #expect(acceptance.event.worldSequence == 1)
            #expect(body.contains("event: snapshot"))
            #expect(body.contains("event: delta"))
            #expect(body.contains("id: 1"))
        }
    }

    @Test("SSE browser origins are allowlisted")
    func streamOriginValidation() async throws {
        let service = TestWorldApplicationService()
        await service.finishNewSubscriptionsImmediately()
        let configuration = try CreatureWorldConfiguration(
            allowedOrigins: ["https://viewer.example"]
        )
        let application = try makeApplication(
            configuration: configuration,
            worldService: service
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/stream?after_sequence=0",
                method: .get,
                headers: [.origin: "https://evil.example"]
            ) { response in
                #expect(response.status == .forbidden)
            }
            try await client.execute(
                uri: "/world/v1/stream?after_sequence=0",
                method: .get,
                headers: [.origin: "https://viewer.example"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("SSE subscription failures require a fresh snapshot")
    func streamFailureRequiresResnapshot() async throws {
        let service = TestWorldApplicationService()
        let application = try makeApplication(worldService: service)

        try await application.test(.router) { client in
            let streamRequest = Task {
                try await client.execute(uri: "/world/v1/stream", method: .get) { response in
                    #expect(response.status == .ok)
                    return String(buffer: response.body)
                }
            }
            while !(await service.snapshotWasRead) {
                await Task.yield()
            }

            await service.failSubscriptions(
                with: WorldSubscriptionError.fellBehind(bufferCapacity: 1)
            )
            let body = try await streamRequest.value

            #expect(body.contains("event: snapshot"))
            #expect(body.contains("event: resnapshot_required"))
            #expect(body.contains("\"error\":\"stream_unavailable\""))
        }
    }

    @Test("Unavailable persistence fails without taking down health routing")
    func unavailablePersistence() async throws {
        let application = try makeApplication(
            worldService: UnavailableWorldApplicationService()
        )

        try await application.test(.router) { client in
            try await client.execute(uri: "/world/v1/events", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "persistence_unavailable")
            }
        }
    }

    @Test("Slow application work fails with an explicit request timeout")
    func requestTimeout() async throws {
        let application = try makeApplication(
            worldService: SlowWorldApplicationService(),
            apiConfiguration: WorldAPIConfiguration(
                maximumRequestDuration: .milliseconds(10)
            )
        )

        try await application.test(.router) { client in
            try await client.execute(uri: "/world/v1/events", method: .get) { response in
                #expect(response.status == .gatewayTimeout)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "request_timeout")
            }
        }
    }

    @Test("Concurrent request saturation fails explicitly without unbounded queuing")
    func requestConcurrencyLimit() async throws {
        let service = BlockingWorldApplicationService()
        let application = try makeApplication(
            worldService: service,
            apiConfiguration: WorldAPIConfiguration(maximumConcurrentRequests: 1)
        )

        try await application.test(.router) { client in
            let firstRequest = Task {
                try await client.execute(uri: "/world/v1/events", method: .get) { response in
                    response.status
                }
            }
            while await !service.hasStarted {
                await Task.yield()
            }

            try await client.execute(uri: "/world/v1/events", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let error = try decode(WorldAPIErrorResponse.self, response.body)
                #expect(error.error == "overloaded")
            }

            await service.release()
            #expect(try await firstRequest.value == .ok)
        }
    }

    private func makeApplication(
        configuration: CreatureWorldConfiguration? = nil,
        worldService: any WorldApplicationService,
        conversationService: any ConversationApplicationService =
            UnavailableConversationApplicationService(),
        characterSessionService: any CharacterSessionApplicationService =
            UnavailableCharacterSessionApplicationService(),
        apiConfiguration: WorldAPIConfiguration = .default
    ) throws -> Application<RouterResponder<BasicRequestContext>> {
        let configuration = try configuration ?? CreatureWorldConfiguration(port: 8080)
        let dependencies = CreatureWorldDependencies.testing(
            configuration: configuration,
            logger: Logger(label: "creature-world-api-tests"),
            buildInfo: CreatureWorldBuildInfo(version: "api-test", schemaVersion: 1),
            worldService: worldService,
            conversationService: conversationService,
            characterSessionService: characterSessionService
        )
        return makeCreatureWorldApplication(
            dependencies: dependencies,
            apiConfiguration: apiConfiguration
        )
    }

    private func makeEvent(
        id: String = "00000000-0000-0000-0000-000000000010"
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            eventID: EventID(validating: id),
            type: WorldEventType(validating: "test.observed"),
            occurredAt: Date(timeIntervalSince1970: 1_725_000_000),
            source: EventSource(
                id: SourceID(validating: "test:http"),
                kind: "test",
                sourceEventID: id
            ),
            subjectIDs: [EntityID(validating: "person:april")],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["message": .string("private test payload")]
        )
    }

    private func makeUtterance(id: String, occurredAt: Date) throws -> PersonUtterance {
        try PersonUtterance(
            utteranceID: UtteranceID(validating: id),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Can you hear me?",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: occurredAt,
            confidence: 1
        )
    }

    private func makeIntent(
        id: String,
        inResponseTo utteranceID: UtteranceID?,
        createdAt: Date
    ) throws -> CharacterUtteranceIntent {
        try CharacterUtteranceIntent(
            responseID: ResponseID(validating: id),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april"),
            inResponseToUtteranceID: utteranceID,
            text: "Loud and clear, April!",
            urgency: 0.4,
            createdAt: createdAt
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> ByteBuffer {
        ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(value))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ buffer: ByteBuffer) throws
        -> Value
    {
        try WorldJSON.makeDecoder().decode(type, from: buffer)
    }
}

private actor TestConversationApplicationService: ConversationApplicationService {
    private var results: [UtteranceID: UtteranceIngressResult] = [:]
    private var responses: [ResponseID: CharacterDeliveryResult] = [:]
    private var subscribers: [ConversationID: ConversationItemStream.Continuation] = [:]
    private(set) var subscriptionCount = 0

    func respond(_ intent: CharacterUtteranceIntent) throws -> CharacterDeliveryResult {
        if let existing = responses[intent.responseID] {
            return CharacterDeliveryResult(
                disposition: .duplicate,
                outcome: existing.outcome,
                conversationItem: existing.conversationItem
            )
        }
        let item = try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(intent.responseID.rawValue)"),
            conversationID: intent.conversationID,
            authorID: intent.characterID,
            authorKind: .character,
            text: intent.text,
            createdAt: intent.createdAt,
            responseID: intent.responseID,
            trace: intent.trace
        )
        let result = CharacterDeliveryResult(
            disposition: .accepted,
            outcome: CharacterDeliveryOutcome(
                attemptID: try DeliveryAttemptID(
                    validating: "delivery-attempt:\(intent.responseID.rawValue)"),
                responseID: intent.responseID,
                route: .communicator,
                state: .accepted,
                occurredAt: intent.createdAt
            ),
            conversationItem: item
        )
        responses[intent.responseID] = result
        subscribers[intent.conversationID]?.yield(.item(item))
        return result
    }

    private var stages: [ResponseID: CharacterDeliveryDecision] = [:]

    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) throws -> CharacterStageResult {
        if let existing = responses[request.responseID] {
            let decision = try makeDecision(
                responseID: request.responseID, recipientID: request.recipientID,
                attemptID: existing.outcome.attemptID)
            return CharacterStageResult(
                disposition: .alreadyDelivered, decision: decision, delivery: nil)
        }
        if let decision = stages[request.responseID] {
            return CharacterStageResult(disposition: .decided, decision: decision)
        }
        let decision = try makeDecision(
            responseID: request.responseID, recipientID: request.recipientID,
            attemptID: DeliveryAttemptID(
                validating: "delivery-attempt:\(request.responseID.rawValue)"))
        stages[request.responseID] = decision
        return CharacterStageResult(disposition: .decided, decision: decision)
    }

    func perform(
        _ performance: CharacterPerformance,
        in conversationID: ConversationID
    ) throws -> CharacterDeliveryResult {
        let intent = performance.intent
        if let existing = responses[intent.responseID] {
            return CharacterDeliveryResult(
                disposition: .duplicate,
                outcome: existing.outcome,
                conversationItem: existing.conversationItem
            )
        }
        guard let decision = stages[intent.responseID],
            decision.attemptID == performance.attemptID
        else { throw WorldContractError.unstagedPerformance }
        let item = try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(intent.responseID.rawValue)"),
            conversationID: intent.conversationID,
            authorID: intent.characterID,
            authorKind: .character,
            text: intent.text,
            createdAt: intent.createdAt,
            responseID: intent.responseID,
            trace: intent.trace
        )
        let result = CharacterDeliveryResult(
            disposition: .accepted,
            outcome: CharacterDeliveryOutcome(
                attemptID: decision.attemptID,
                responseID: intent.responseID,
                route: decision.route,
                state: performance.outcome.state,
                occurredAt: intent.createdAt,
                providerReference: performance.outcome.providerReference,
                errorCode: performance.outcome.errorCode
            ),
            conversationItem: item
        )
        responses[intent.responseID] = result
        subscribers[intent.conversationID]?.yield(.item(item))
        return result
    }

    private func makeDecision(
        responseID: ResponseID, recipientID: EntityID, attemptID: DeliveryAttemptID
    ) throws -> CharacterDeliveryDecision {
        let now = Date(timeIntervalSince1970: 1_789_100_000)
        return try CharacterDeliveryDecision(
            attemptID: attemptID,
            responseID: responseID,
            route: .physicalSpeech,
            privacyMode: .notApplicable,
            reason: .homeAndAudible,
            decidedAt: now,
            presence: PersonPresence(
                personID: recipientID, state: .home, confidence: 1, observedAt: now,
                validUntil: now, physicallyAudible: true, basis: .assumed)
        )
    }

    func ingest(_ utterance: PersonUtterance) throws -> UtteranceIngressResult {
        if let existing = results[utterance.utteranceID] {
            return UtteranceIngressResult(
                disposition: .duplicate,
                percept: existing.percept,
                conversationItem: existing.conversationItem
            )
        }
        let item = try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(utterance.utteranceID.rawValue)"),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            utteranceID: utterance.utteranceID,
            trace: utterance.trace
        )
        let percept = try PersonUtterancePercept(
            characterID: utterance.addresseeIDs[0],
            utterance: utterance,
            priorConversationItems: orderedItems
        )
        let result = UtteranceIngressResult(
            disposition: .accepted,
            percept: percept,
            conversationItem: item
        )
        results[utterance.utteranceID] = result
        subscribers[utterance.conversationID]?.yield(.item(item))
        return result
    }

    func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID?,
        limit: Int
    ) -> CharacterDeliveryPage {
        let all = responses.values
            .filter { $0.conversationItem.conversationID == conversationID }
            .sorted { $0.conversationItem.createdAt < $1.conversationItem.createdAt }
        let start =
            responseID.flatMap { id in all.firstIndex { $0.outcome.responseID == id } }
            .map { $0 + 1 } ?? 0
        let remaining = Array(all.dropFirst(start))
        let page = remaining.prefix(limit).map { result in
            CharacterDeliveryRecord(
                intent: try! CharacterUtteranceIntent(
                    responseID: result.outcome.responseID,
                    conversationID: conversationID,
                    characterID: result.conversationItem.authorID,
                    recipientID: try! EntityID(validating: "person:april"),
                    text: result.conversationItem.text,
                    urgency: 0.4,
                    createdAt: result.conversationItem.createdAt
                ),
                decision: try! CharacterDeliveryDecision(
                    attemptID: result.outcome.attemptID,
                    responseID: result.outcome.responseID,
                    route: .communicator,
                    privacyMode: .private,
                    reason: .presenceUncertain,
                    decidedAt: result.conversationItem.createdAt,
                    presence: PersonPresence(
                        personID: try! EntityID(validating: "person:april"),
                        state: .unknown,
                        confidence: 0,
                        observedAt: result.conversationItem.createdAt,
                        validUntil: result.conversationItem.createdAt,
                        physicallyAudible: false
                    )
                ),
                outcome: result.outcome,
                conversationItem: result.conversationItem
            )
        }
        return CharacterDeliveryPage(
            deliveries: page,
            nextResponseID: page.last?.intent.responseID,
            hasMore: remaining.count > limit
        )
    }

    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) -> ConversationItemPage {
        let all = orderedItems.filter { $0.conversationID == conversationID }
        let start = itemID.flatMap { id in all.firstIndex { $0.itemID == id } }.map { $0 + 1 } ?? 0
        let remaining = Array(all.dropFirst(start))
        let page = Array(remaining.prefix(limit))
        return ConversationItemPage(
            items: page,
            nextItemID: page.last?.itemID,
            hasMore: remaining.count > limit
        )
    }

    func subscribe(to conversationID: ConversationID) -> ConversationItemStream {
        let (stream, continuation) = ConversationItemStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        subscribers[conversationID] = continuation
        subscriptionCount = subscribers.count
        return stream
    }

    func finishSubscriptions() {
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
        subscriptionCount = 0
    }

    func finishConversationSubscriptions() {
        finishSubscriptions()
    }

    private var orderedItems: [ConversationItem] {
        (results.values.map(\.conversationItem) + responses.values.map(\.conversationItem)).sorted {
            ($0.createdAt, $0.itemID.rawValue) < ($1.createdAt, $1.itemID.rawValue)
        }
    }
}

private actor TestWorldApplicationService: WorldApplicationService {
    private var storedEvents: [WorldEventEnvelope] = []
    private var finishNewSubscriptions = false
    private var subscriber: WorldDeltaStream.Continuation?
    private(set) var snapshotWasRead = false

    func accept(_ proposedEvent: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        if let existing = storedEvents.first(where: { $0.eventID == proposedEvent.eventID }) {
            return WorldEventAcceptance(disposition: .duplicateEvent, event: existing)
        }
        if let sourceEventID = proposedEvent.source.sourceEventID,
            let existing = storedEvents.first(where: {
                $0.source.id == proposedEvent.source.id
                    && $0.source.sourceEventID == sourceEventID
            })
        {
            return WorldEventAcceptance(disposition: .duplicateSourceEvent, event: existing)
        }
        var event = proposedEvent
        event.receivedAt = Date(timeIntervalSince1970: 1_725_000_001)
        event.worldSequence = Int64(storedEvents.count + 1)
        storedEvents.append(event)
        subscriber?.yield(WorldDelta(event: event, changedFacts: []))
        return WorldEventAcceptance(disposition: .accepted, event: event)
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        let matches = storedEvents.filter { ($0.worldSequence ?? 0) > sequence }
        let pageEvents = Array(matches.prefix(limit))
        return WorldEventPage(
            events: pageEvents,
            nextSequence: pageEvents.last?.worldSequence ?? sequence,
            hasMore: matches.count > limit
        )
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
        WorldFactPage(facts: [], nextFactID: nil, hasMore: false)
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        WorldTimerPage(timers: [], nextTimerID: nil, hasMore: false)
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        snapshotWasRead = true
        return WorldSnapshot(
            latestSequence: storedEvents.last?.worldSequence ?? 0,
            facts: [],
            timers: [],
            factsTruncated: false,
            timersTruncated: false
        )
    }

    func subscribe() async throws -> WorldDeltaStream {
        let shouldFinish = finishNewSubscriptions
        return WorldDeltaStream { continuation in
            if shouldFinish {
                continuation.finish()
            } else {
                subscriber = continuation
            }
        }
    }

    func finishNewSubscriptionsImmediately() {
        finishNewSubscriptions = true
    }

    func finishSubscriptions() async {
        subscriber?.finish()
        subscriber = nil
    }

    func failSubscriptions(with error: WorldSubscriptionError) {
        subscriber?.finish(throwing: error)
        subscriber = nil
    }

    var eventCount: Int {
        storedEvents.count
    }
}

private struct SlowWorldApplicationService: WorldApplicationService {
    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        throw WorldAPIError.databaseUnavailable
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        try await Task.sleep(for: .seconds(60))
        throw WorldAPIError.databaseUnavailable
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
        throw WorldAPIError.databaseUnavailable
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        throw WorldAPIError.databaseUnavailable
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        throw WorldAPIError.databaseUnavailable
    }

    func subscribe() async throws -> WorldDeltaStream {
        throw WorldAPIError.databaseUnavailable
    }

    func finishSubscriptions() async {}
}

private actor BlockingWorldApplicationService: WorldApplicationService {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        throw WorldAPIError.databaseUnavailable
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return WorldEventPage(events: [], nextSequence: sequence, hasMore: false)
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
        throw WorldAPIError.databaseUnavailable
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        throw WorldAPIError.databaseUnavailable
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        throw WorldAPIError.databaseUnavailable
    }

    func subscribe() async throws -> WorldDeltaStream {
        throw WorldAPIError.databaseUnavailable
    }

    func finishSubscriptions() async {}

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

extension HTTPFields {
    fileprivate var withJSONContentType: HTTPFields {
        var fields = self
        fields[.contentType] = "application/json"
        return fields
    }
}

private actor InMemorySessionRepository: CharacterSessionRepository {
    private var sessions: [CharacterSessionID: CharacterSession] = [:]

    func session(for characterID: EntityID) -> CharacterSession? {
        sessions.values.filter { $0.characterID == characterID }.max {
            $0.loggedInAt < $1.loggedInAt
        }
    }

    func session(id: CharacterSessionID) -> CharacterSession? { sessions[id] }

    func save(_ session: CharacterSession) { sessions[session.sessionID] = session }

    func latestSessions() -> [CharacterSession] {
        Dictionary(grouping: sessions.values, by: \.characterID).values.compactMap {
            $0.max { $0.loggedInAt < $1.loggedInAt }
        }
    }
}
