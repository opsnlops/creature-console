import Foundation
import Testing

@testable import Common
@testable import creature_cli

@Suite("sACN Remote Protocol")
struct SACNRemoteProtocolTests {

    @Test("Hello JSON encodes type and round-trips")
    func helloRoundTrip() throws {
        let hello = SACNRemoteHello(viewerName: "Studio", viewerVersion: "2.16.2", universe: 7)
        let data = try JSONEncoder().encode(hello)

        let decoded = try JSONDecoder().decode(SACNRemoteHello.self, from: data)
        #expect(decoded.type == "hello")
        #expect(decoded.viewerName == "Studio")
        #expect(decoded.viewerVersion == "2.16.2")
        #expect(decoded.universe == 7)
    }

    @Test("Network sacn-listen parses CLI options")
    func parseNetworkListenOptions() throws {
        let command = try CreatureCLI.Network.SACNListen.parse([
            "--interface", "en0",
            "--port", "1963",
            "--universe", "2",
            "--max-clients", "12",
        ])

        #expect(command.interface == "en0")
        #expect(command.port == 1963)
        #expect(command.universe == 2)
        #expect(command.maxClients == 12)
        #expect(command.listInterfaces == false)
    }

    @Test("Network sacn-listen defaults stay stable")
    func networkListenDefaults() throws {
        let command = try CreatureCLI.Network.SACNListen.parse([])

        #expect(command.interface == nil)
        #expect(command.port == 1963)
        #expect(command.universe == nil)
        #expect(command.maxClients == 8)
        #expect(command.listInterfaces == false)
    }
}
