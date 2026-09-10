import CreatureCommunicatorGateway
import Foundation
import Testing

@Suite("Creature Communicator Gateway configuration")
struct CommunicatorGatewayConfigurationTests {
    @Test("Defaults bind only to loopback on the independent gateway port")
    func defaults() {
        #expect(CommunicatorGatewayConfiguration.default.host == "127.0.0.1")
        #expect(CommunicatorGatewayConfiguration.default.port == 8_001)
    }

    @Test("Environment overrides JSON configuration")
    func precedence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let configurationURL = temporaryDirectory.appending(path: "gateway.json")
        try Data(#"{"host":"192.0.2.10","port":9000}"#.utf8).write(to: configurationURL)

        let configuration = try CommunicatorGatewayConfiguration.load(
            from: configurationURL,
            environment: [
                CommunicatorGatewayConfiguration.hostEnvironmentKey: "0.0.0.0",
                CommunicatorGatewayConfiguration.portEnvironmentKey: "9100",
            ]
        )

        #expect(configuration.host == "0.0.0.0")
        #expect(configuration.port == 9_100)
    }

    @Test("Invalid hosts and ports fail explicitly")
    func validation() {
        #expect(throws: CommunicatorGatewayConfigurationError.emptyHost) {
            try CommunicatorGatewayConfiguration(host: "   ")
        }
        #expect(throws: CommunicatorGatewayConfigurationError.invalidPort(0)) {
            try CommunicatorGatewayConfiguration(port: 0)
        }
        #expect(
            throws: CommunicatorGatewayConfigurationError.invalidEnvironmentValue(
                name: "SERVER_PORT",
                value: "many"
            )
        ) {
            try CommunicatorGatewayConfiguration.load(
                from: nil,
                environment: [CommunicatorGatewayConfiguration.portEnvironmentKey: "many"]
            )
        }
    }
}
