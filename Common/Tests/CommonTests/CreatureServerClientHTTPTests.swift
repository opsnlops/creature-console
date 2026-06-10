import Foundation
import Testing

@testable import Common

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif


@Suite("CreatureServerClient HTTP helpers")
struct CreatureServerClientHTTPTests {

    actor CountingHTTPResponder {
        private var count = 0
        private let statusCode: Int
        private let data: Data

        init(statusCode: Int, data: Data) {
            self.statusCode = statusCode
            self.data = data
        }

        func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
            count += 1

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!

            return (data, response)
        }

        func requestCount() -> Int {
            count
        }
    }

    @Test("playlist upsert does not replay successful non-status response")
    func playlistUpsertDoesNotReplaySuccessfulNonStatusResponse() async throws {
        let playlist = Playlist(id: "playlist-1", name: "Test Playlist", items: [])
        let responseData = try JSONEncoder().encode(playlist)
        let responder = CountingHTTPResponder(statusCode: 201, data: responseData)
        let client = CreatureServerClient(httpDataLoader: { request in
            try await responder.load(request)
        })

        try client.connect(
            serverHostname: "example.test",
            serverPort: 443,
            useTLS: true,
            serverProxyHost: nil,
            apiKey: nil
        )

        let result = await client.createPlaylist(playlist)

        switch result {
        case .success(let message):
            #expect(message == "Saved 'Test Playlist' to server")
        case .failure(let error):
            Issue.record("Expected success, got \(error.localizedDescription)")
        }

        let requestCount = await responder.requestCount()
        #expect(requestCount == 1)
    }
}
