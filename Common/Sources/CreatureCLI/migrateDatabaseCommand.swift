import ArgumentParser
import Foundation
import MongoKitten

extension CreatureCLI.Util {

    struct MigrateDatabase: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "migrate-database",
            abstract: "Copy the creature database from the mainline server to the travel server",
            discussion: """
                Connects directly to MongoDB on both servers and copies every collection \
                (documents and indexes) from the mainline server to the travel server. The \
                travel server's copy of the database is replaced so it exactly mirrors the \
                mainline server.

                Servers may be given as a hostname or IP (the default port \
                \(MongoServerAddress.defaultPort) is assumed), host:port, or a full \
                mongodb:// URI.
                """
        )

        @Option(help: "Hostname or IP of the mainline (source) MongoDB server")
        var mainlineServer: String

        @Option(help: "Hostname or IP of the travel (destination) MongoDB server")
        var travelServer: String

        @Option(help: "Name of the database to migrate")
        var database: String = "creature_server"

        @Option(help: "Number of documents to copy per batch")
        var batchSize: Int = 500

        @Flag(help: "Show what would be copied without writing anything")
        var dryRun: Bool = false

        @Flag(name: [.customLong("yes"), .customShort("y")], help: "Skip the confirmation prompt")
        var assumeYes: Bool = false

        @OptionGroup()
        var globalOptions: GlobalOptions

        func validate() throws {
            guard batchSize > 0 else {
                throw ValidationError("--batch-size must be greater than zero")
            }
        }

        func run() async throws {
            let plan = MigrationPlan(
                mainlineServer: mainlineServer,
                travelServer: travelServer,
                database: database,
                batchSize: batchSize,
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
    let travelServer: String
    let database: String
    let batchSize: Int
    let dryRun: Bool
    let assumeYes: Bool

    private struct CollectionResult {
        let name: String
        let documents: Int
        let indexes: Int
    }

    func execute() async throws {
        let mainlineURI = try MongoServerAddress.connectionURI(
            for: mainlineServer, database: database)
        let travelURI = try MongoServerAddress.connectionURI(
            for: travelServer, database: database)

        print("Connecting to mainline server at \(mainlineServer)...")
        let source: MongoDatabase
        do {
            source = try await MongoDatabase.connect(to: mainlineURI)
        } catch {
            throw failWithMessage(
                "Unable to connect to the mainline server (\(mainlineServer)): \(error)")
        }

        print("Connecting to travel server at \(travelServer)...")
        let destination: MongoDatabase
        do {
            destination = try await MongoDatabase.connect(to: travelURI)
        } catch {
            throw failWithMessage(
                "Unable to connect to the travel server (\(travelServer)): \(error)")
        }

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
            "This will REPLACE database '\(database)' on the travel server (\(travelServer)).")
        print("Type 'yes' to continue: ", terminator: "")
        guard let answer = readLine(), answer.lowercased() == "yes" else {
            throw failWithMessage("Migration cancelled.")
        }
        print("")
    }

    private func copy(
        collection name: String, from source: MongoDatabase, to destination: MongoDatabase
    ) async throws -> CollectionResult {
        let sourceCollection = source[name]
        let destinationCollection = destination[name]

        print("Copying \(name)...")
        try await destinationCollection.drop()

        var copied = 0
        var batch: [Document] = []
        batch.reserveCapacity(batchSize)

        for try await document in sourceCollection.find() {
            batch.append(document)
            if batch.count >= batchSize {
                copied += try await insert(batch: batch, into: destinationCollection, named: name)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            copied += try await insert(batch: batch, into: destinationCollection, named: name)
        }

        let indexes = try await copyIndexes(
            from: sourceCollection, to: destinationCollection, named: name)

        print("  \(formatNumber(UInt64(copied))) documents, \(indexes) indexes")
        return CollectionResult(name: name, documents: copied, indexes: indexes)
    }

    private func insert(
        batch: [Document], into collection: MongoCollection, named name: String
    ) async throws -> Int {
        let reply = try await collection.insertMany(batch)
        guard reply.ok == 1, reply.writeErrors?.isEmpty != false else {
            throw failWithMessage(
                "Insert into '\(name)' on the travel server failed: \(reply.debugDescription)")
        }
        return reply.insertCount
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

        print("")
        printTable(
            results,
            columns: [
                TableColumn(title: "Collection") { $0.name },
                TableColumn(title: "Documents") { formatNumber(UInt64($0.documents)) },
                TableColumn(title: "Indexes") { String($0.indexes) },
            ])
        print("")
        print(
            "Done! Copied \(formatNumber(UInt64(totalDocuments))) documents in "
                + "\(results.count) collections from \(mainlineServer) to \(travelServer).")
    }
}
