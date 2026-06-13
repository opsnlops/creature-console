import Foundation

/// Normalizes user-supplied MongoDB server addresses into full connection URIs.
///
/// Accepts a bare hostname or IP (`travel.local`, `10.3.2.11`), a host with a port
/// (`travel.local:27018`), an IPv6 literal (`::1` or `[::1]:27017`), or a complete
/// `mongodb://` / `mongodb+srv://` URI. The result always carries a database name in
/// its path so MongoKitten connects to the right database.
enum MongoServerAddress {

    static let defaultPort = 27017

    enum AddressError: Error, LocalizedError, Equatable {
        case emptyAddress
        case unsupportedScheme(String)
        case invalidPort(String)
        case invalidAddress(String)

        var errorDescription: String? {
            switch self {
            case .emptyAddress:
                return "Server address is empty"
            case .unsupportedScheme(let scheme):
                return
                    "Unsupported URI scheme '\(scheme)' — use mongodb:// or mongodb+srv://, or just a hostname"
            case .invalidPort(let port):
                return "'\(port)' is not a valid port number"
            case .invalidAddress(let address):
                return "'\(address)' is not a valid server address"
            }
        }
    }

    /// Builds a MongoDB connection URI for the given server address and database.
    static func connectionURI(for server: String, database: String) throws -> String {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AddressError.emptyAddress
        }

        if let schemeRange = trimmed.range(of: "://") {
            let scheme = String(trimmed[..<schemeRange.lowerBound])
            guard scheme == "mongodb" || scheme == "mongodb+srv" else {
                throw AddressError.unsupportedScheme(scheme)
            }
            return ensureDatabase(in: trimmed, after: schemeRange.upperBound, database: database)
        }

        let hostAndPort = try normalizeHostAndPort(trimmed)
        return "mongodb://\(hostAndPort)/\(database)"
    }

    /// Inserts the database name into a full URI's path if the URI doesn't already have one,
    /// preserving any query string (e.g. `?authSource=admin`).
    private static func ensureDatabase(
        in uri: String, after authorityStart: String.Index, database: String
    ) -> String {
        let afterScheme = uri[authorityStart...]

        let queryStart = afterScheme.firstIndex(of: "?")
        let mainPart = queryStart.map { afterScheme[..<$0] } ?? afterScheme
        let query = queryStart.map { String(afterScheme[$0...]) } ?? ""
        let prefix = String(uri[..<authorityStart])

        if let slash = mainPart.firstIndex(of: "/") {
            let path = mainPart[mainPart.index(after: slash)...]
            if path.isEmpty {
                return "\(prefix)\(mainPart)\(database)\(query)"
            }
            return uri
        }

        return "\(prefix)\(mainPart)/\(database)\(query)"
    }

    /// Normalizes a bare `host`, `host:port`, `ipv6`, or `[ipv6]:port` value into
    /// a `host:port` authority string suitable for a mongodb:// URI.
    private static func normalizeHostAndPort(_ address: String) throws -> String {
        // Bracketed IPv6, possibly with a port: [::1] or [::1]:27017
        if address.hasPrefix("[") {
            guard let closingBracket = address.firstIndex(of: "]") else {
                throw AddressError.invalidAddress(address)
            }
            let host = String(address[...closingBracket])
            let remainder = address[address.index(after: closingBracket)...]
            if remainder.isEmpty {
                return "\(host):\(defaultPort)"
            }
            guard remainder.hasPrefix(":") else {
                throw AddressError.invalidAddress(address)
            }
            let port = try validatedPort(String(remainder.dropFirst()))
            return "\(host):\(port)"
        }

        let colonCount = address.filter { $0 == ":" }.count

        // More than one colon and no brackets means a bare IPv6 literal like ::1
        if colonCount > 1 {
            return "[\(address)]:\(defaultPort)"
        }

        if colonCount == 1 {
            let parts = address.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                throw AddressError.invalidAddress(address)
            }
            let port = try validatedPort(String(parts[1]))
            return "\(parts[0]):\(port)"
        }

        return "\(address):\(defaultPort)"
    }

    private static func validatedPort(_ value: String) throws -> Int {
        guard let port = Int(value), (1...65535).contains(port) else {
            throw AddressError.invalidPort(value)
        }
        return port
    }
}
