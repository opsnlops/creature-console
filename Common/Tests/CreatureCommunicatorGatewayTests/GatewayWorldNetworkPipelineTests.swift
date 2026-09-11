import BeakyCommunicatorCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
import WorldCore

@testable import CreatureCommunicatorGateway

@Suite("Gateway to World network pipeline")
struct GatewayWorldNetworkPipelineTests {
    @Test("Owned HTTP client shuts down when gateway startup is cancelled")
    func startupCancellationCleansUpHTTPClient() async {
        let service = CommunicatorGatewayHTTPClientService()
        let task = Task {
            try await service.run()
        }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
        } catch is CancellationError {
            // Cancellation is the expected startup-failure path.
        } catch {
            Issue.record("Unexpected shutdown error: \(error)")
        }
    }

    @Test("Actual HTTP hop carries submission, history, and live updates")
    func completePipeline() async throws {
        let utterance = try makeUtterance()
        let result = try makeResult(for: utterance)
        let recorder = NetworkWorldRecorder()
        let worldApplication = makeWorldShapedApplication(result: result, recorder: recorder)

        try await worldApplication.test(.live) { worldClient in
            let worldPort = try #require(worldClient.port)
            let upstream = HTTPCommunicatorWorldUpstream(
                baseURL: URL(string: "http://localhost:\(worldPort)/world/v1")!
            )
            let gateway = makeCommunicatorGatewayApplication(
                registry: ForegroundLeaseRegistry(),
                upstream: upstream
            )

            try await gateway.test(.router) { gatewayClient in
                try await gatewayClient.execute(
                    uri: "/communicator/v1/health",
                    method: .get
                ) { response in
                    #expect(response.status == .ok)
                }
                try await gatewayClient.execute(
                    uri: "/communicator/v1/conversations/conversation:april-beaky/utterances",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(utterance))
                ) { response in
                    #expect(response.status == .accepted)
                }
                try await gatewayClient.execute(
                    uri: "/communicator/v1/conversations/conversation:april-beaky/items?limit=100",
                    method: .get
                ) { response in
                    #expect(response.status == .ok)
                    let page = try WorldJSON.makeDecoder().decode(
                        ConversationItemPage.self,
                        from: response.body
                    )
                    #expect(page.items == [result.conversationItem])
                }
                try await gatewayClient.execute(
                    uri: "/communicator/v1/conversations/conversation:april-beaky/stream",
                    method: .get
                ) { response in
                    #expect(response.status == .ok)
                    #expect(String(buffer: response.body).contains("event: item"))
                }
            }
        }

        #expect(await recorder.utterances == [utterance])
        #expect(await recorder.routeConversationIDs == ["conversation:april-beaky"])
    }

    private func makeWorldShapedApplication(
        result: UtteranceIngressResult,
        recorder: NetworkWorldRecorder
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        let routes = router.group("world")
        routes.get("v1/health") { _, _ in
            Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #"{"status":"ok"}"#)))
        }
        routes.post("v1/conversations/:conversationID/utterances") { request, context in
            await recorder.recordRouteConversationID(context.parameters.get("conversationID"))
            let body = try await request.body.collect(upTo: 1_048_576)
            let utterance = try WorldJSON.makeDecoder().decode(PersonUtterance.self, from: body)
            await recorder.record(utterance)
            return try jsonResponse(result, status: .accepted)
        }
        routes.get("v1/conversations/:conversationID/items") { _, _ in
            try jsonResponse(
                ConversationItemPage(
                    items: [result.conversationItem],
                    nextItemID: result.conversationItem.itemID,
                    hasMore: false
                )
            )
        }
        routes.get("v1/conversations/:conversationID/stream") { _, _ in
            Response(
                status: .ok,
                headers: [.contentType: "text/event-stream; charset=utf-8"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        string: "event: ready\ndata: {}\n\nevent: item\ndata: {}\n\n"
                    )
                )
            )
        }
        return Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
    }

    private func jsonResponse<Value: Encodable>(
        _ value: Value,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(
                byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(value))
            )
        )
    }

    private func makeUtterance() throws -> PersonUtterance {
        try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:network-pipeline"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "One pipeline, all the way through",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:network-test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_200_000),
            confidence: 1
        )
    }

    private func makeResult(for utterance: PersonUtterance) throws -> UtteranceIngressResult {
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:network-pipeline"),
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

private actor NetworkWorldRecorder {
    private(set) var utterances: [PersonUtterance] = []
    private(set) var routeConversationIDs: [String?] = []

    func record(_ utterance: PersonUtterance) {
        utterances.append(utterance)
    }

    func recordRouteConversationID(_ conversationID: String?) {
        routeConversationIDs.append(conversationID)
    }
}
