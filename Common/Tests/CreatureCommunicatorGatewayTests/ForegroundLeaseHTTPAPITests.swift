import BeakyCommunicatorCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
import WorldCore

@testable import CreatureCommunicatorGateway

@Suite("Communicator gateway foreground lease API")
struct ForegroundLeaseHTTPAPITests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let command = ForegroundLeaseCommand(
        installationID: CommunicatorInstallationID(
            rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        ),
        sessionID: ForegroundSessionID(
            rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
    )

    @Test("Acquire, renew, and release use one session-safe JSON contract")
    func lifecycle() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)
        let application = makeCommunicatorGatewayApplication(registry: registry)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .post,
                headers: [.contentType: "application/json"],
                body: try encode(command)
            ) { response in
                #expect(response.status == .created)
                let lease = try decode(ForegroundLease.self, response.body)
                #expect(lease.expiresAt == now.addingTimeInterval(90))
            }

            try await clock.advance(by: 30)
            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .put,
                headers: [.contentType: "application/json"],
                body: try encode(command)
            ) { response in
                #expect(response.status == .ok)
                let lease = try decode(ForegroundLease.self, response.body)
                #expect(lease.expiresAt == now.addingTimeInterval(120))
            }

            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .delete,
                headers: [.contentType: "application/json"],
                body: try encode(command)
            ) { response in
                #expect(response.status == .noContent)
            }
        }

        #expect(await !registry.hasActiveLease())
    }

    @Test("Expired and unknown sessions cannot renew")
    func unknownRenewal() async throws {
        let application = makeCommunicatorGatewayApplication(
            registry: ForegroundLeaseRegistry(clock: ManualWorldClock(now: now))
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .put,
                headers: [.contentType: "application/json"],
                body: try encode(command)
            ) { response in
                #expect(response.status == .notFound)
                let error = try decode(CommunicatorGatewayErrorResponse.self, response.body)
                #expect(error.error == "lease_not_found")
            }
        }
    }

    @Test("Untrusted request bodies are bounded and validated")
    func requestValidation() async throws {
        let application = makeCommunicatorGatewayApplication(
            registry: ForegroundLeaseRegistry(clock: ManualWorldClock(now: now))
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .post,
                body: ByteBuffer(string: "{}")
            ) { response in
                #expect(response.status == .unsupportedMediaType)
            }

            try await client.execute(
                uri: "/world/communicator/v1/foreground-leases",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(repeating: 0x41, count: 4_097)
            ) { response in
                #expect(response.status == .contentTooLarge)
            }
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> ByteBuffer {
        ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(value))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ body: ByteBuffer) throws -> Value {
        try WorldJSON.makeDecoder().decode(type, from: body)
    }
}
