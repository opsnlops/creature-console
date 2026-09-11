import Common
import CreatureAppSupport
import Foundation
import Testing
import WorldCore

@Suite("World conversation HTTP client")
struct WorldConversationClientTests {
    @Test("Submission uses the typed world route and proxy headers")
    func submitsThroughProxy() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let loader = RecordingLoader(response: result)
        let connection = CreatureServiceConnection(
            hostname: "server.prod.chirpchirp.dev",
            port: 443,
            usesTLS: true,
            proxyHostname: "proxy.prod.chirpchirp.dev",
            proxyAPIKey: "secret"
        )
        let client = WorldConversationClient(connection: connection, loader: loader)

        #expect(try await client.submit(utterance) == result)
        let request = try #require(await loader.lastRequest)
        #expect(
            request.url?.absoluteString
                == "https://proxy.prod.chirpchirp.dev/world/v1/conversations/conversation:april-beaky/utterances"
        )
        #expect(request.value(forHTTPHeaderField: "Host") == "server.prod.chirpchirp.dev:443")
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == "secret")
        #expect(
            try WorldJSON.makeDecoder().decode(PersonUtterance.self, from: request.httpBody!)
                == utterance)
    }

    @Test("LAN history requests stay credential-free and preserve the cursor")
    func loadsLANHistory() async throws {
        let utterance = try Self.makeUtterance()
        let result = try Self.makeResult(for: utterance)
        let page = ConversationItemPage(
            items: [result.conversationItem],
            nextItemID: result.conversationItem.itemID,
            hasMore: false
        )
        let loader = RecordingLoader(response: page)
        let client = WorldConversationClient(
            connection: CreatureServiceConnection(
                hostname: "10.69.66.1",
                port: 8_000,
                usesTLS: false
            ),
            loader: loader
        )

        #expect(
            try await client.items(
                in: utterance.conversationID,
                after: result.conversationItem.itemID,
                limit: 25
            ) == page
        )
        let request = try #require(await loader.lastRequest)
        #expect(request.url?.host == "10.69.66.1")
        #expect(request.url?.port == 8_000)
        #expect(request.url?.query?.contains("limit=25") == true)
        #expect(request.url?.query?.contains("after_item_id=") == true)
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == nil)
    }

    private static func makeUtterance() throws -> PersonUtterance {
        try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:client-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Hello over the wire",
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
            itemID: ConversationItemID(validating: "conversation-item:client-test"),
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

private actor RecordingLoader<Response: Encodable & Sendable>: HTTPDataLoading {
    private let encodedResponse: Data
    private(set) var lastRequest: URLRequest?

    init(response: Response) {
        encodedResponse = try! WorldJSON.makeEncoder().encode(response)
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (encodedResponse, response)
    }
}
