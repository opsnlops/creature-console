import BeakyCommunicatorCore
import Common
import CreatureAppSupport
import Foundation
import Testing
import WorldCore

@Suite("Communicator foreground lease HTTP client")
struct ForegroundLeaseHTTPClientTests {
    private let installation = CommunicatorInstallationID(
        rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    )
    private let session = ForegroundSessionID(
        rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )

    @Test("Proxy requests use the world communicator route and shared proxy headers")
    func proxyRequest() async throws {
        let loader = LeaseRecordingLoader(statusCodes: [201])
        let client = ForegroundLeaseHTTPClient(
            connection: CreatureServiceConnection(
                hostname: "server.prod.chirpchirp.dev",
                port: 443,
                usesTLS: true,
                proxyHostname: "proxy.prod.chirpchirp.dev",
                proxyAPIKey: "secret"
            ),
            loader: loader
        )

        try await client.acquireForegroundLease(
            installationID: installation,
            sessionID: session
        )

        let request = try #require(await loader.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                == "https://proxy.prod.chirpchirp.dev/world/communicator/v1/foreground-leases"
        )
        #expect(request.value(forHTTPHeaderField: "Host") == "server.prod.chirpchirp.dev:443")
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == "secret")
        #expect(
            try WorldJSON.makeDecoder().decode(
                ForegroundLeaseCommand.self,
                from: request.httpBody!
            ) == ForegroundLeaseCommand(installationID: installation, sessionID: session)
        )
    }

    @Test("LAN lifecycle requests remain credential-free")
    func lanLifecycle() async throws {
        let loader = LeaseRecordingLoader(statusCodes: [201, 200, 204])
        let client = ForegroundLeaseHTTPClient(
            connection: CreatureServiceConnection(
                hostname: "10.69.66.1",
                port: 8_001,
                usesTLS: false
            ),
            loader: loader
        )

        try await client.acquireForegroundLease(
            installationID: installation,
            sessionID: session
        )
        #expect(
            try await client.renewForegroundLease(
                installationID: installation,
                sessionID: session
            )
        )
        try await client.releaseForegroundLease(
            installationID: installation,
            sessionID: session
        )

        let requests = await loader.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "DELETE"])
        #expect(requests.allSatisfy { $0.url?.host == "10.69.66.1" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-acw-api-key") == nil })
    }

    @Test("A missing server lease asks the heartbeat to reacquire")
    func missingLease() async throws {
        let loader = LeaseRecordingLoader(statusCodes: [404])
        let client = ForegroundLeaseHTTPClient(
            connection: CreatureServiceConnection(
                hostname: "10.69.66.1",
                port: 8_001,
                usesTLS: false
            ),
            loader: loader
        )

        #expect(
            try await !client.renewForegroundLease(
                installationID: installation,
                sessionID: session
            )
        )
    }
}

private actor LeaseRecordingLoader: HTTPDataLoading {
    private var statusCodes: [Int]
    private(set) var requests: [URLRequest] = []

    init(statusCodes: [Int]) {
        self.statusCodes = statusCodes
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let statusCode = statusCodes.removeFirst()
        return (
            Data(),
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
