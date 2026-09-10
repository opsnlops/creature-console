import BeakyCommunicatorCore
import Common
import Foundation
import WorldCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum ForegroundLeaseHTTPClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case unexpectedResponse
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The communicator gateway address is invalid"
        case .unexpectedResponse:
            "The communicator gateway returned an invalid response"
        case .requestFailed(let statusCode):
            "The communicator gateway returned HTTP status \(statusCode)"
        }
    }
}

public struct ForegroundLeaseHTTPClient: ForegroundLeaseTransport, Sendable {
    private let connection: CreatureServiceConnection
    private let loader: any HTTPDataLoading

    public init(
        connection: CreatureServiceConnection,
        loader: any HTTPDataLoading = URLSession.shared
    ) {
        self.connection = connection
        self.loader = loader
    }

    public func acquireForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws {
        let response = try await execute(
            method: "POST",
            command: ForegroundLeaseCommand(
                installationID: installationID,
                sessionID: sessionID
            )
        )
        try validateSuccess(response)
    }

    public func renewForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws -> Bool {
        let response = try await execute(
            method: "PUT",
            command: ForegroundLeaseCommand(
                installationID: installationID,
                sessionID: sessionID
            )
        )
        guard response.statusCode != 404 else { return false }
        try validateSuccess(response)
        return true
    }

    public func releaseForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws {
        let response = try await execute(
            method: "DELETE",
            command: ForegroundLeaseCommand(
                installationID: installationID,
                sessionID: sessionID
            )
        )
        try validateSuccess(response)
    }

    private func execute(
        method: String,
        command: ForegroundLeaseCommand
    ) async throws -> HTTPURLResponse {
        guard
            let url = URL(
                string: connection.baseURLString(
                    transport: .http,
                    pathPrefix: "/communicator/v1/foreground-leases"
                )
            )
        else {
            throw ForegroundLeaseHTTPClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try WorldJSON.makeEncoder().encode(command)
        connection.applyProxyHeaders(to: &request)

        let (_, response) = try await loader.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForegroundLeaseHTTPClientError.unexpectedResponse
        }
        return response
    }

    private func validateSuccess(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw ForegroundLeaseHTTPClientError.requestFailed(
                statusCode: response.statusCode
            )
        }
    }
}
