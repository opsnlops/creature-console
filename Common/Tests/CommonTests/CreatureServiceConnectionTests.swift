import Foundation
import Testing

@testable import Common

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite("Creature service connection")
struct CreatureServiceConnectionTests {
    @Test("Trusted LAN routes directly without authentication headers")
    func trustedLANRoute() throws {
        let connection = CreatureServiceConnection(
            hostname: "10.69.66.1",
            port: 8_000,
            usesTLS: false
        )
        let urlString = connection.baseURLString(transport: .http, pathPrefix: "/world/v1")
        var request = URLRequest(url: try #require(URL(string: urlString)))
        connection.applyProxyHeaders(to: &request)

        #expect(urlString == "http://10.69.66.1:8000/world/v1")
        #expect(!connection.usesProxy)
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == nil)
        #expect(request.value(forHTTPHeaderField: "Host") == nil)
    }

    @Test("External ingress keeps the logical host and API key")
    func externalProxyRoute() throws {
        let connection = CreatureServiceConnection(
            hostname: "server.prod.chirpchirp.dev",
            port: 443,
            usesTLS: true,
            proxyHostname: "proxy.prod.chirpchirp.dev",
            proxyAPIKey: "family-secret"
        )
        let urlString = connection.baseURLString(transport: .http, pathPrefix: "world/v1")
        var request = URLRequest(url: try #require(URL(string: urlString)))
        connection.applyProxyHeaders(to: &request)

        #expect(urlString == "https://proxy.prod.chirpchirp.dev/world/v1")
        #expect(connection.usesProxy)
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == "family-secret")
        #expect(request.value(forHTTPHeaderField: "Host") == "server.prod.chirpchirp.dev:443")
    }

    @Test("A partial proxy configuration never leaks its API key")
    func partialProxyConfiguration() throws {
        let connection = CreatureServiceConnection(
            hostname: "server.prod.chirpchirp.dev",
            port: 443,
            usesTLS: true,
            proxyAPIKey: "must-not-leak"
        )
        let urlString = connection.baseURLString(transport: .websocket, pathPrefix: "/api/v1")
        var request = URLRequest(url: try #require(URL(string: urlString)))
        connection.applyProxyHeaders(to: &request)

        #expect(urlString == "wss://server.prod.chirpchirp.dev:443/api/v1")
        #expect(!connection.usesProxy)
        #expect(request.value(forHTTPHeaderField: "x-acw-api-key") == nil)
    }
}
