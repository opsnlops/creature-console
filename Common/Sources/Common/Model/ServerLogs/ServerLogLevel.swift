

import Foundation

public enum ServerLogLevel: Int, CaseIterable {
    case trace = 0
    case debug = 1
    case info = 2
    case warn = 3
    case error = 4
    case critical = 5
    case off = 6
    case unknown = 7

    public var description: String {
        switch self {
            case .trace: return "trace"
            case .debug: return "debug"
            case .info: return "info"
            case .warn: return "warning"
            case .error: return "error"
            case .critical: return "critical"
            case .off: return "off"
            case .unknown: return "unknown"
        }
    }

    public init(from string: String) {
        switch string.lowercased() {
            case "trace": self = .trace
            case "debug": self = .debug
            case "info": self = .info
            case "warning": self = .warn
            case "error": self = .error
            case "critical": self = .critical
            case "off": self = .off
            default: self = .unknown
        }
    }

}
