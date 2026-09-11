import Common
import Foundation

public enum CreatureAppFamily {
    public static let proxyKeychainService = "io.opsnlops.CreatureConsole"
    public static let proxyAPIKeyAccount = "proxyApiKey"
    public static let sharedKeychainAccessGroupInfoKey = "CreatureSharedKeychainAccessGroup"

    public static let accentRed = 0.750
    public static let accentGreen = 0.569
    public static let accentBlue = 0.971
}

public struct CreatureServiceSettings: Equatable, Sendable {
    public var hostname: String
    public var port: Int
    public var usesTLS: Bool
    public var usesProxy: Bool
    public var proxyHostname: String

    public init(
        hostname: String,
        port: Int,
        usesTLS: Bool,
        usesProxy: Bool,
        proxyHostname: String
    ) {
        self.hostname = hostname
        self.port = port
        self.usesTLS = usesTLS
        self.usesProxy = usesProxy
        self.proxyHostname = proxyHostname
    }

    public func connection(proxyAPIKey: String?) -> CreatureServiceConnection {
        CreatureServiceConnection(
            hostname: hostname,
            port: port,
            usesTLS: usesTLS,
            proxyHostname: usesProxy ? proxyHostname : nil,
            proxyAPIKey: usesProxy ? proxyAPIKey : nil
        )
    }
}
