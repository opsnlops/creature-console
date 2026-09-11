import Foundation
import Logging
import ServiceLifecycle

public struct CommunicatorGatewayBuildInfo: Codable, Equatable, Sendable {
    public static let current = CommunicatorGatewayBuildInfo(version: "0.1.3")

    public let version: String

    public init(version: String) {
        self.version = version
    }
}

public struct CommunicatorGatewayHealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let service: String
    public let buildVersion: String

    public init(status: String, service: String, buildVersion: String) {
        self.status = status
        self.service = service
        self.buildVersion = buildVersion
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case service
        case buildVersion = "build_version"
    }
}

struct CommunicatorGatewayLifecycleReporter: Service, Sendable {
    let logger: Logger

    func run() async throws {
        try await gracefulShutdown()
        logger.info("Creature Communicator Gateway shutdown complete")
    }
}
