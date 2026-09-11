import Testing

@testable import CreatureAppSupport

@Suite("Creature app-family settings")
struct CreatureServiceSettingsTests {
    @Test("Proxy settings produce one shared connection contract")
    func proxyConnection() {
        let settings = CreatureServiceSettings(
            hostname: "server.prod.chirpchirp.dev",
            port: 443,
            usesTLS: true,
            usesProxy: true,
            proxyHostname: "proxy.prod.chirpchirp.dev"
        )

        let connection = settings.connection(proxyAPIKey: "secret")

        #expect(connection.hostname == "server.prod.chirpchirp.dev")
        #expect(connection.proxyHostname == "proxy.prod.chirpchirp.dev")
        #expect(connection.proxyAPIKey == "secret")
        #expect(connection.usesProxy)
    }

    @Test("Disabling proxy omits both proxy routing and credentials")
    func directConnection() {
        let settings = CreatureServiceSettings(
            hostname: "10.69.66.1",
            port: 8_000,
            usesTLS: false,
            usesProxy: false,
            proxyHostname: "proxy.prod.chirpchirp.dev"
        )

        let connection = settings.connection(proxyAPIKey: "secret")

        #expect(connection.proxyHostname == nil)
        #expect(connection.proxyAPIKey == nil)
        #expect(!connection.usesProxy)
    }
}
