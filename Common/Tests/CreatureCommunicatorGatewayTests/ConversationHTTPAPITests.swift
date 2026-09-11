import BeakyCommunicatorCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
import WorldCore

@testable import CreatureCommunicatorGateway

@Suite("Communicator gateway conversation API")
struct ConversationHTTPAPITests {
    @Test("Submission crosses the gateway with the shared typed contract")
    func submission() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let upstream = RecordingWorldUpstream(result: result)
        let application = makeApplication(upstream: upstream)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/communicator/v1/conversations/conversation:april-beaky/utterances",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(utterance))
            ) { response in
                #expect(response.status == .accepted)
                let decoded = try decode(UtteranceIngressResult.self, response.body)
                #expect(decoded == result)
            }
        }

        #expect(await upstream.submittedUtterances == [utterance])
    }

    @Test("History pagination is forwarded without changing order")
    func history() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let page = ConversationItemPage(
            items: [result.conversationItem],
            nextItemID: result.conversationItem.itemID,
            hasMore: false
        )
        let upstream = RecordingWorldUpstream(result: result, page: page)
        let application = makeApplication(upstream: upstream)

        try await application.test(.router) { client in
            try await client.execute(
                uri:
                    "/communicator/v1/conversations/conversation:april-beaky/items?limit=25&after_item_id=conversation-item:before",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let decoded = try decode(ConversationItemPage.self, response.body)
                #expect(decoded == page)
            }
        }

        let request = try #require(await upstream.itemRequests.first)
        #expect(request.conversationID == utterance.conversationID)
        #expect(request.after?.rawValue == "conversation-item:before")
        #expect(request.limit == 25)
    }

    @Test("Live SSE bytes are streamed through the gateway")
    func liveStream() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let upstream = RecordingWorldUpstream(
            result: result,
            streamBytes: [
                ByteBuffer(string: "event: ready\ndata: {}\n\n"),
                ByteBuffer(string: "event: item\ndata: {}\n\n"),
            ]
        )
        let application = makeApplication(upstream: upstream)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/communicator/v1/conversations/conversation:april-beaky/stream",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/event-stream; charset=utf-8")
                #expect(
                    String(buffer: response.body)
                        == "event: ready\ndata: {}\n\nevent: item\ndata: {}\n\n"
                )
            }
        }
    }

    @Test("Invalid requests stop at the gateway boundary")
    func validation() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let upstream = RecordingWorldUpstream(result: result)
        let application = makeApplication(upstream: upstream)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/communicator/v1/conversations/conversation:different/utterances",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(utterance))
            ) { response in
                #expect(response.status == .conflict)
            }
            try await client.execute(
                uri: "/communicator/v1/conversations/conversation:april-beaky/items?limit=501",
                method: .get
            ) { response in
                #expect(response.status == .badRequest)
            }
        }

        #expect(await upstream.submittedUtterances.isEmpty)
        #expect(await upstream.itemRequests.isEmpty)
    }

    @Test("Unavailable World fails readiness and conversation traffic without stopping gateway")
    func unavailableWorld() async throws {
        let application = makeApplication(upstream: UnavailableWorldUpstream())

        try await application.test(.router) { client in
            try await client.execute(uri: "/communicator/v1/health", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let health = try decode(CommunicatorGatewayHealthResponse.self, response.body)
                #expect(health.status == "unavailable")
            }
            try await client.execute(
                uri: "/communicator/v1/conversations/conversation:april-beaky/items",
                method: .get
            ) { response in
                #expect(response.status == .serviceUnavailable)
                let error = try decode(CommunicatorGatewayErrorResponse.self, response.body)
                #expect(error.error == "world_unavailable")
            }
        }
    }

    private func makeApplication(upstream: any CommunicatorWorldUpstream)
        -> Application<RouterResponder<BasicRequestContext>>
    {
        makeCommunicatorGatewayApplication(
            registry: ForegroundLeaseRegistry(),
            upstream: upstream
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ body: ByteBuffer) throws -> Value {
        try WorldJSON.makeDecoder().decode(type, from: body)
    }

    private static func makeUtterance() throws -> PersonUtterance {
        try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:gateway-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Can you hear me through the gateway?",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_200_000),
            confidence: 1
        )
    }

    private static func makeResult(for utterance: PersonUtterance) throws
        -> UtteranceIngressResult
    {
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:gateway-test"),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            utteranceID: utterance.utteranceID
        )
        return UtteranceIngressResult(
            disposition: .accepted,
            percept: try PersonUtterancePercept(
                characterID: utterance.addresseeIDs[0],
                utterance: utterance,
                priorConversationItems: []
            ),
            conversationItem: item
        )
    }
}

private actor RecordingWorldUpstream: CommunicatorWorldUpstream {
    struct ItemRequest: Sendable {
        let conversationID: ConversationID
        let after: ConversationItemID?
        let limit: Int
    }

    private let result: UtteranceIngressResult
    private let page: ConversationItemPage
    private let streamBytes: [ByteBuffer]
    private(set) var submittedUtterances: [PersonUtterance] = []
    private(set) var itemRequests: [ItemRequest] = []

    init(
        result: UtteranceIngressResult,
        page: ConversationItemPage = ConversationItemPage(
            items: [],
            nextItemID: nil,
            hasMore: false
        ),
        streamBytes: [ByteBuffer] = []
    ) {
        self.result = result
        self.page = page
        self.streamBytes = streamBytes
    }

    func health() async throws {}

    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        submittedUtterances.append(utterance)
        return result
    }

    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
        itemRequests.append(
            ItemRequest(conversationID: conversationID, after: itemID, limit: limit))
        return page
    }

    func conversationStream(
        for conversationID: ConversationID
    ) async throws -> GatewayConversationByteStream {
        return GatewayConversationByteStream { continuation in
            for buffer in streamBytes {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }
}

private struct UnavailableWorldUpstream: CommunicatorWorldUpstream {
    struct Unavailable: Error {}

    func health() async throws { throw Unavailable() }

    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        throw Unavailable()
    }

    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
        throw Unavailable()
    }

    func conversationStream(
        for conversationID: ConversationID
    ) async throws -> GatewayConversationByteStream {
        throw Unavailable()
    }
}
