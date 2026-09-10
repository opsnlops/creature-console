import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Connection and ingress-proxy configuration shared by Creature clients.
///
/// The logical service remains the request's `Host` when traffic crosses the external proxy.
/// Trusted-LAN connections omit both proxy headers and remain credential-free.
public struct CreatureServiceConnection: Equatable, Sendable {
    public enum Transport: Sendable {
        case http
        case websocket
    }

    public var hostname: String
    public var port: Int
    public var usesTLS: Bool
    public var proxyHostname: String?
    public var proxyAPIKey: String?

    public init(
        hostname: String,
        port: Int,
        usesTLS: Bool,
        proxyHostname: String? = nil,
        proxyAPIKey: String? = nil
    ) {
        self.hostname = hostname
        self.port = port
        self.usesTLS = usesTLS
        self.proxyHostname = proxyHostname
        self.proxyAPIKey = proxyAPIKey
    }

    public var usesProxy: Bool {
        normalizedProxyHostname != nil && normalizedProxyAPIKey != nil
    }

    public func baseURLString(
        transport: Transport,
        pathPrefix: String
    ) -> String {
        let scheme =
            switch transport {
            case .http: usesTLS ? "https" : "http"
            case .websocket: usesTLS ? "wss" : "ws"
            }
        let authority = normalizedProxyHostname ?? "\(hostname):\(port)"
        let normalizedPath = pathPrefix.hasPrefix("/") ? pathPrefix : "/\(pathPrefix)"
        return "\(scheme)://\(authority)\(normalizedPath)"
    }

    public func applyProxyHeaders(to request: inout URLRequest) {
        guard normalizedProxyHostname != nil, let apiKey = normalizedProxyAPIKey else { return }

        request.setValue(apiKey, forHTTPHeaderField: "x-acw-api-key")
        request.setValue("\(hostname):\(port)", forHTTPHeaderField: "Host")
    }

    private var normalizedProxyHostname: String? {
        guard let proxyHostname = proxyHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
            !proxyHostname.isEmpty,
            normalizedProxyAPIKey != nil
        else { return nil }
        return proxyHostname
    }

    private var normalizedProxyAPIKey: String? {
        guard let proxyAPIKey = proxyAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            !proxyAPIKey.isEmpty
        else { return nil }
        return proxyAPIKey
    }
}
