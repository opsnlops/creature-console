import ArgumentParser
import CreatureMigration
import Foundation
import MongoKitten

extension CreatureCLI.Util {

    struct MigrateDatabase: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "migrate-database",
            abstract: "Merge the creature database from the mainline server into the travel server",
            discussion: """
                Connects directly to MongoDB on both servers and merges every collection \
                (documents and indexes) from the mainline server into the travel server. \
                Documents are matched by _id: ones that exist on both servers are \
                overwritten with the mainline copy (the mainline server always wins), and \
                documents that only exist on the travel server are left alone.

                Servers may be given as a hostname or IP (the default port \
                \(MongoServerAddress.defaultPort) is assumed), host:port, or a full \
                mongodb:// URI.
                """
        )

        @Option(help: "Hostname or IP of the mainline (source) MongoDB server")
        var mainlineServer: String

        @Option(help: "Port of the mainline MongoDB server")
        var mainlinePort: Int = MongoServerAddress.defaultPort

        @Option(help: "Hostname or IP of the travel (destination) MongoDB server")
        var travelServer: String

        @Option(help: "Port of the travel MongoDB server")
        var travelPort: Int = MongoServerAddress.defaultPort

        @Option(help: "Name of the database to migrate")
        var database: String = "creature_server"

        @Flag(help: "Show what would be copied without writing anything")
        var dryRun: Bool = false

        @Flag(name: [.customLong("yes"), .customShort("y")], help: "Skip the confirmation prompt")
        var assumeYes: Bool = false

        @OptionGroup()
        var globalOptions: GlobalOptions

        func run() async throws {
            let plan = MigrationPlan(
                mainlineServer: mainlineServer,
                mainlinePort: mainlinePort,
                travelServer: travelServer,
                travelPort: travelPort,
                database: database,
                dryRun: dryRun,
                assumeYes: assumeYes
            )
            try await tracedRun("util.migrate-database", config: globalOptions) {
                try await plan.execute()
            }
        }
    }
}

/// The full source → destination database copy, separated from the ArgumentParser
/// plumbing so it can run inside the traced `@Sendable` closure.
private struct MigrationPlan: Sendable {
    let mainlineServer: String
    let mainlinePort: Int
    let travelServer: String
    let travelPort: Int
    let database: String
    let dryRun: Bool
    let assumeYes: Bool

    private struct CollectionResult {
        let name: String
        let documents: Int
        let added: Int
        let updated: Int
        let indexes: Int

        var unchanged: Int { documents - added - updated }
    }

    func execute() async throws {
        let source = try await connectCreatureDatabase(
            server: mainlineServer, port: mainlinePort, database: database, role: "mainline")
        let destination = try await connectCreatureDatabase(
            server: travelServer, port: travelPort, database: database, role: "travel")

        let collections = try await sourceCollections(in: source)
        guard !collections.isEmpty else {
            throw failWithMessage(
                "Database '\(database)' on the mainline server has no collections to copy.")
        }

        try await printPreview(of: collections)

        if dryRun {
            print("Dry run — nothing was copied.")
            return
        }

        try confirmOverwriteIfNeeded()

        var results: [CollectionResult] = []
        for collection in collections {
            let result = try await copy(
                collection: collection.name, from: source, to: destination)
            results.append(result)
        }

        printSummary(of: results)
    }

    /// All user collections in the source database, sorted by name for stable output.
    private func sourceCollections(in source: MongoDatabase) async throws -> [MongoCollection] {
        let collections = try await source.listCollections()
        return
            collections
            .filter { !$0.name.hasPrefix("system.") }
            .sorted { $0.name < $1.name }
    }

    private func printPreview(of collections: [MongoCollection]) async throws {
        var counts: [(name: String, count: Int)] = []
        for collection in collections {
            counts.append((collection.name, try await collection.count()))
        }

        print("")
        print("Database '\(database)' on the mainline server:")
        printTable(
            counts,
            columns: [
                TableColumn(title: "Collection") { $0.name },
                TableColumn(title: "Documents") { formatNumber(UInt64($0.count)) },
            ])
        print("")
    }

    private func confirmOverwriteIfNeeded() throws {
        guard !assumeYes else { return }

        print(
            "This will merge database '\(database)' from the mainline server into the travel "
                + "server (\(travelServer)). Documents that exist on both servers will be "
                + "overwritten with the mainline copy.")
        print("Type 'yes' to continue: ", terminator: "")
        guard let answer = readLine(), answer.lowercased() == "yes" else {
            throw failWithMessage("Migration cancelled.")
        }
        print("")
    }

    /// Merges one collection: every mainline document is upserted into the travel server
    /// by `_id`, so mainline always wins and travel-only documents are left alone.
    private func copy(
        collection name: String, from source: MongoDatabase, to destination: MongoDatabase
    ) async throws -> CollectionResult {
        let sourceCollection = source[name]
        let destinationCollection = destination[name]

        print("Merging \(name)...")

        var documents = 0
        var added = 0
        var updated = 0

        for try await document in sourceCollection.find() {
            guard let id = document["_id"] else {
                throw failWithMessage(
                    "A document in '\(name)' on the mainline server has no _id; "
                        + "refusing to continue.")
            }

            let reply = try await destinationCollection.upsert(document, where: ["_id": id])
            guard reply.ok == 1, reply.writeErrors?.isEmpty != false else {
                throw failWithMessage(
                    "Upsert into '\(name)' on the travel server failed: \(reply)")
            }

            documents += 1
            if reply.upserted?.isEmpty == false {
                added += 1
            } else if reply.updatedCount > 0 {
                updated += 1
            }
        }

        let indexes = try await copyIndexes(
            from: sourceCollection, to: destinationCollection, named: name)

        print(
            "  \(formatNumber(UInt64(documents))) documents "
                + "(\(added) added, \(updated) updated), \(indexes) indexes")
        return CollectionResult(
            name: name, documents: documents, added: added, updated: updated, indexes: indexes)
    }

    /// Re-creates the source collection's non-`_id` indexes on the destination. Index
    /// creation failures (e.g. an option MongoDB 4.4 doesn't support) are reported as
    /// warnings so one exotic index can't abort the whole migration.
    private func copyIndexes(
        from source: MongoCollection, to destination: MongoCollection, named name: String
    ) async throws -> Int {
        let sourceIndexes = try await source.listIndexes().drain()

        let indexes =
            sourceIndexes
            .filter { $0.name != "_id_" }
            .map { index -> CreateIndexes.Index in
                var newIndex = CreateIndexes.Index(named: index.name, keys: index.key)
                newIndex.unique = index.unique
                newIndex.sparse = index.sparse
                newIndex.expireAfterSeconds = index.expireAfterSeconds.map(Int.init)
                return newIndex
            }

        guard !indexes.isEmpty else { return 0 }

        do {
            try await destination.createIndexes(indexes)
        } catch {
            print(
                "  Warning: couldn't re-create indexes on '\(name)': \(error). "
                    + "The documents were copied; create the indexes manually if needed.")
            return 0
        }
        return indexes.count
    }

    private func printSummary(of results: [CollectionResult]) {
        let totalDocuments = results.reduce(0) { $0 + $1.documents }
        let totalAdded = results.reduce(0) { $0 + $1.added }
        let totalUpdated = results.reduce(0) { $0 + $1.updated }

        print("")
        printTable(
            results,
            columns: [
                TableColumn(title: "Collection") { $0.name },
                TableColumn(title: "Documents") { formatNumber(UInt64($0.documents)) },
                TableColumn(title: "Added") { String($0.added) },
                TableColumn(title: "Updated") { String($0.updated) },
                TableColumn(title: "Unchanged") { String($0.unchanged) },
                TableColumn(title: "Indexes") { String($0.indexes) },
            ])
        print("")
        print(
            "Done! Merged \(formatNumber(UInt64(totalDocuments))) documents "
                + "(\(totalAdded) added, \(totalUpdated) updated) in \(results.count) "
                + "collections from \(mainlineServer) into \(travelServer).")
    }
}
