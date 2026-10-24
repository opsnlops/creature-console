import Foundation
import Logging
import MongoKitten

@testable import creature_world

/// The database a test run writes to (#247): `MONGODB_TEST_URI`'s server and options, with a
/// database of this run's own - `creature_world_test_<unix seconds>_<random>` - so a run starts
/// empty and never reads what earlier runs left. Every run used to write into one
/// `creature_world` and leave its rows there. Queries that read across a whole collection - the
/// newest fifty light readings, every order's status, every overwritten keeping - found other
/// runs' rows in place of their own, and the scene opener slowed until the black-box test lost a
/// race (#266). Nil when `MONGODB_TEST_URI` is unset, and the MongoDB suites are skipped.
enum TestDatabase {
    /// The server every MongoDB suite is given, from the environment.
    private static let base = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

    /// This run's database name.
    static let name: String = {
        let suffix = String(UUID().uuidString.lowercased().prefix(6))
        let name =
            "\(CreatureWorldConfiguration.testDatabasePrefix)\(Int(Date().timeIntervalSince1970))_\(suffix)"
        if let base { Task.detached { await dropStaleRuns(on: base, keeping: name) } }
        return name
    }()

    static let uri: String? = base.map { replacingDatabase(in: $0, with: name) }

    /// A database of its own within the run, for a suite that runs a World process. The World
    /// runs its rules over everything it can see: the black-box World's delivery sweep settled
    /// `HousePresenceTests`' orders before that test's own sweep could (#247).
    static func isolated(_ label: String) -> String? {
        base.map { replacingDatabase(in: $0, with: "\(name)_\(label)") }
    }

    /// How old a run's database is before a later run drops it: a day, so no run going on at
    /// the same time is touched.
    static let staleAfter: TimeInterval = 86_400

    /// `uri` with its database named `name`, the options kept: `mongodb://host:port/db?opts`.
    static func replacingDatabase(in uri: String, with name: String) -> String {
        let scheme = "mongodb://"
        guard uri.hasPrefix(scheme) else { return uri }
        let rest = uri.dropFirst(scheme.count)
        let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        let authority = rest[..<authorityEnd]
        var path = rest[authorityEnd...]
        if path.hasPrefix("/") { path = path.dropFirst() }
        let options = path.firstIndex(of: "?").map { String(path[$0...]) } ?? ""
        return "\(scheme)\(authority)/\(name)\(options)"
    }

    /// When a run's database was made, from its name; nil for any other database.
    static func madeAt(_ name: String) -> Date? {
        guard name.hasPrefix(CreatureWorldConfiguration.testDatabasePrefix) else { return nil }
        let stamp = name.dropFirst(CreatureWorldConfiguration.testDatabasePrefix.count)
            .split(separator: "_").first
        return stamp.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }

    /// Drops earlier runs' databases more than `staleAfter` old, best effort: a run that cannot
    /// reach the server has nothing to drop.
    private static func dropStaleRuns(on uri: String, keeping current: String) async {
        guard let cluster = try? await MongoCluster(connectingTo: ConnectionSettings(uri)) else {
            return
        }
        defer { Task { await cluster.disconnect() } }
        let now = Date()
        for database in (try? await cluster.listDatabases()) ?? [] {
            guard !database.name.hasPrefix(current), let made = madeAt(database.name),
                now.timeIntervalSince(made) > staleAfter
            else { continue }
            try? await database.drop()
        }
    }
}
