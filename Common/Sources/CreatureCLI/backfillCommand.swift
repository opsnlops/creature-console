import ArgumentParser
import Common
import CreatureMigration
import Foundation
import MongoKitten

extension CreatureCLI.Util {

    struct Backfill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "backfill",
            abstract:
                "Copy road-created animations, dialog scripts, and storyboards from the travel server back into the mainline server",
            discussion: """
                The reverse of migrate-database, scoped to the content you create on the road: \
                animations, dialog scripts, and storyboards. Entities are matched by their UUID \
                `id` (the Mongo `_id` is ignored).

                By default this is add-only — only items whose id is missing from the mainline \
                server are copied, and existing mainline documents are never modified. Pass \
                --update-existing to also overwrite items that already exist.

                Dialog scripts reference the creatures that speak their turns, and storyboards \
                reference animations, creatures, fixtures, playlists, and dialog scripts. Before \
                copying an item whose references are missing on the mainline server, you are \
                prompted to copy it anyway, pull the missing items across too, skip it, or abort. \
                With --yes, items that have missing references are skipped (run interactively to \
                decide per item).

                After writing, the mainline creature-server is told to invalidate the caches \
                for the collections that changed (so connected consoles re-pull the data). \
                That call goes to the server named by the global --host/--port options — point \
                them at the mainline creature-server. Use --skip-cache-invalidation to disable.

                Servers may be given as a hostname or IP (the default port \
                \(MongoServerAddress.defaultPort) is assumed), host:port, or a full mongodb:// URI.
                """
        )

        @Option(help: "Hostname or IP of the mainline (destination) MongoDB server")
        var mainlineServer: String

        @Option(help: "Port of the mainline MongoDB server")
        var mainlinePort: Int = MongoServerAddress.defaultPort

        @Option(help: "Hostname or IP of the travel (source) MongoDB server")
        var travelServer: String

        @Option(help: "Port of the travel MongoDB server")
        var travelPort: Int = MongoServerAddress.defaultPort

        @Option(help: "Name of the database")
        var database: String = "creature_server"

        @Flag(help: "Also overwrite items that already exist on the mainline server")
        var updateExisting: Bool = false

        @Flag(help: "Show what would be copied without writing anything")
        var dryRun: Bool = false

        @Flag(
            name: [.customLong("yes"), .customShort("y")],
            help: "Skip prompts; items with missing references are skipped")
        var assumeYes: Bool = false

        @Flag(help: "Don't tell the mainline server to invalidate its caches afterward")
        var skipCacheInvalidation: Bool = false

        @OptionGroup()
        var globalOptions: GlobalOptions

        func run() async throws {
            // The cache-invalidation call goes to the mainline creature-server's HTTP API,
            // which is configured by the global --host/--port options (not the Mongo host).
            let server = getServer(config: globalOptions)
            let plan = BackfillPlan(
                mainlineServer: mainlineServer,
                mainlinePort: mainlinePort,
                travelServer: travelServer,
                travelPort: travelPort,
                database: database,
                updateExisting: updateExisting,
                dryRun: dryRun,
                assumeYes: assumeYes,
                skipCacheInvalidation: skipCacheInvalidation,
                server: server
            )
            try await tracedRun("util.backfill", config: globalOptions) {
                try await plan.execute()
            }
        }
    }
}

/// Copies road-created content from the travel server back into the mainline server,
/// matching on the UUID `id` and resolving each item's references first.
private struct BackfillPlan: Sendable {
    let mainlineServer: String
    let mainlinePort: Int
    let travelServer: String
    let travelPort: Int
    let database: String
    let updateExisting: Bool
    let dryRun: Bool
    let assumeYes: Bool
    let skipCacheInvalidation: Bool
    let server: CreatureServerClient

    /// Reference collections content can point at that live in the database.
    /// (Sounds are referenced by file name and live on disk, so they're not here.)
    private static let referenceCollections = [
        "animations", "creatures", "playlists", "dialog_scripts", "fixtures",
    ]

    /// A travel document selected for back-fill.
    private struct PlannedDoc {
        let uuid: String
        let title: String
        let document: Document
        let isNew: Bool
    }

    /// A reference that is missing on the mainline server.
    private struct MissingDependency {
        let reference: EntityReference
        let name: String?
        let sourceDocument: Document?
        var canCopy: Bool { sourceDocument != nil }
    }

    /// A planned item plus the analysis of its references.
    private struct ContentAnalysis {
        let doc: PlannedDoc
        let missing: [MissingDependency]
        let unverifiableSounds: [String]
    }

    /// Tally of what one collection's apply step did.
    private struct ApplyResult {
        var added = 0
        var updated = 0
        var skipped = 0
        var dependenciesCopied = 0
    }

    private enum MissingChoice {
        case copyAnyway
        case copyDeps
        case skip
        case abort
    }

    func execute() async throws {
        // travel is the source (where road content was made); mainline is the destination.
        let source = try await connectCreatureDatabase(
            server: travelServer, port: travelPort, database: database, role: "travel")
        let destination = try await connectCreatureDatabase(
            server: mainlineServer, port: mainlinePort, database: database, role: "mainline")

        // Plan each back-filled collection.
        let plannedAnimations = try await planCollection(
            "animations", from: source, to: destination, titleProvider: animationTitle)
        let plannedDialogScripts = try await planCollection(
            "dialog_scripts", from: source, to: destination, titleProvider: titleField)
        let plannedStoryboards = try await planCollection(
            "storyboards", from: source, to: destination, titleProvider: titleField)

        // UUID sets that will exist on the destination after this run, used for reference
        // checks — so an item that points at an animation or dialog script we're also
        // copying in this run isn't flagged as missing.
        var destinationIds: [String: Set<String>] = [:]
        for collection in Self.referenceCollections {
            destinationIds[collection] = try await uuidSet(of: collection, in: destination)
        }
        destinationIds["animations", default: []].formUnion(plannedAnimations.map(\.uuid))
        destinationIds["dialog_scripts", default: []].formUnion(plannedDialogScripts.map(\.uuid))

        let dialogAnalyses = try await analyzeReferences(
            plannedDialogScripts, collection: "dialog_scripts", source: source,
            destinationIds: destinationIds)
        let storyboardAnalyses = try await analyzeReferences(
            plannedStoryboards, collection: "storyboards", source: source,
            destinationIds: destinationIds)

        printPreview(
            animations: plannedAnimations, dialogScripts: dialogAnalyses,
            storyboards: storyboardAnalyses)

        if dryRun {
            print("Dry run — nothing was copied.")
            return
        }
        if plannedAnimations.isEmpty && dialogAnalyses.isEmpty && storyboardAnalyses.isEmpty {
            print("Nothing to back-fill — the mainline server is already up to date.")
            return
        }

        try confirmIfNeeded()

        // Collections we actually wrote to, so we invalidate exactly those caches afterward.
        var modifiedCollections = Set<String>()

        // Plain content (no references) first, then reference-bearing content in dependency
        // order: dialog scripts before storyboards, since storyboards can reference them.
        let animationResult = try await applyPlain(
            plannedAnimations, collection: "animations", into: destination,
            modified: &modifiedCollections)
        let dialogResult = try await applyReferenceBearing(
            dialogAnalyses, collection: "dialog_scripts", into: destination,
            modified: &modifiedCollections)
        let storyboardResult = try await applyReferenceBearing(
            storyboardAnalyses, collection: "storyboards", into: destination,
            modified: &modifiedCollections)

        printSummary(
            animations: animationResult, dialogScripts: dialogResult, storyboards: storyboardResult)

        await invalidateCaches(for: modifiedCollections)
    }

    // MARK: - Planning

    /// Selects the travel documents to back-fill from a collection. Add-only keeps only
    /// documents whose `id` is missing on the destination; `--update-existing` keeps all.
    private func planCollection(
        _ name: String, from source: MongoDatabase, to destination: MongoDatabase,
        titleProvider: (Document) -> String
    ) async throws -> [PlannedDoc] {
        let existing = try await uuidSet(of: name, in: destination)

        var planned: [PlannedDoc] = []
        for try await document in source[name].find() {
            guard let uuid = document["id"] as? String, !uuid.isEmpty else {
                // Without a UUID id we can't identify it; skip rather than guess.
                continue
            }
            let isNew = !existing.contains(uuid)
            guard isNew || updateExisting else { continue }
            planned.append(
                PlannedDoc(
                    uuid: uuid, title: titleProvider(document), document: document, isNew: isNew))
        }
        return planned.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Resolves each item's references against the destination, collecting the ones that are
    /// missing (with their travel copy, if any, for the copy-the-dependency option).
    private func analyzeReferences(
        _ planned: [PlannedDoc], collection: String, source: MongoDatabase,
        destinationIds: [String: Set<String>]
    ) async throws -> [ContentAnalysis] {
        var analyses: [ContentAnalysis] = []
        for item in planned {
            var missing: [MissingDependency] = []
            var sounds: [String] = []
            var seen = Set<EntityReference>()

            for reference in ContentReferences.references(in: item.document, collection: collection)
            {
                guard seen.insert(reference).inserted else { continue }
                guard let refCollection = reference.kind.collection else {
                    sounds.append(reference.identifier)
                    continue
                }
                if destinationIds[refCollection]?.contains(reference.identifier) == true {
                    continue
                }

                let sourceDocument = try await source[refCollection].findOne([
                    "id": reference.identifier
                ])
                let name =
                    sourceDocument.flatMap { ($0["name"] as? String) ?? ($0["title"] as? String) }
                missing.append(
                    MissingDependency(
                        reference: reference, name: name, sourceDocument: sourceDocument))
            }
            analyses.append(
                ContentAnalysis(
                    doc: item, missing: missing,
                    unverifiableSounds: Array(Set(sounds)).sorted()
                ))
        }
        return analyses
    }

    // MARK: - Applying

    /// Copies content that doesn't carry references (animations) straight across.
    private func applyPlain(
        _ planned: [PlannedDoc], collection: String, into destination: MongoDatabase,
        modified: inout Set<String>
    ) async throws -> ApplyResult {
        var result = ApplyResult()
        guard !planned.isEmpty else { return result }

        print("Copying \(collection)...")
        for item in planned {
            let inserted = try await upsertByUUID(
                item.document, uuid: item.uuid, into: destination[collection],
                label: "\(singular(collection)) '\(item.title)'")
            if inserted { result.added += 1 } else { result.updated += 1 }
        }
        modified.insert(collection)
        return result
    }

    /// Copies reference-bearing content, prompting per item when references are missing.
    private func applyReferenceBearing(
        _ analyses: [ContentAnalysis], collection: String, into destination: MongoDatabase,
        modified: inout Set<String>
    ) async throws -> ApplyResult {
        var result = ApplyResult()
        guard !analyses.isEmpty else { return result }

        print("Copying \(collection)...")
        for analysis in analyses {
            if !analysis.missing.isEmpty {
                let choice = assumeYes ? .skip : promptForMissing(analysis, collection: collection)
                switch choice {
                case .abort:
                    throw failWithMessage("Back-fill aborted.")
                case .skip:
                    print("  Skipped \(singular(collection)) '\(analysis.doc.title)'.")
                    result.skipped += 1
                    continue
                case .copyDeps:
                    for dependency in analysis.missing {
                        guard let document = dependency.sourceDocument,
                            let depCollection = dependency.reference.kind.collection
                        else { continue }
                        _ = try await upsertByUUID(
                            document, uuid: dependency.reference.identifier,
                            into: destination[depCollection],
                            label:
                                "\(dependency.reference.kind.label) '\(dependency.name ?? dependency.reference.identifier)'"
                        )
                        result.dependenciesCopied += 1
                        modified.insert(depCollection)
                    }
                case .copyAnyway:
                    break
                }
            }

            let inserted = try await upsertByUUID(
                analysis.doc.document, uuid: analysis.doc.uuid, into: destination[collection],
                label: "\(singular(collection)) '\(analysis.doc.title)'")
            if inserted { result.added += 1 } else { result.updated += 1 }
            modified.insert(collection)
        }
        return result
    }

    // MARK: - Database helpers

    /// All UUID `id` values present in a destination collection.
    private func uuidSet(of collection: String, in db: MongoDatabase) async throws -> Set<String> {
        var ids = Set<String>()
        for try await document in db[collection].find().project(["id": 1]) {
            if let id = document["id"] as? String { ids.insert(id) }
        }
        return ids
    }

    /// Upserts a document into a collection matched on its UUID `id`. Returns true if the
    /// document was newly inserted, false if it replaced an existing one.
    @discardableResult
    private func upsertByUUID(
        _ document: Document, uuid: String, into collection: MongoCollection, label: String
    ) async throws -> Bool {
        let reply = try await collection.upsert(document, where: ["id": uuid])
        guard reply.ok == 1, reply.writeErrors?.isEmpty != false else {
            throw failWithMessage("Failed to copy \(label) to the mainline server: \(reply)")
        }
        let inserted = reply.upserted?.isEmpty == false
        print("  \(inserted ? "Added" : "Updated") \(label)")
        return inserted
    }

    // MARK: - Cache invalidation

    /// Asks the mainline creature-server to invalidate the caches for the collections we
    /// just wrote to, so connected consoles re-pull the new data. The data is already in
    /// the database, so a failed invalidation is reported as a warning rather than fatal.
    private func invalidateCaches(for collections: Set<String>) async {
        guard !skipCacheInvalidation, !collections.isEmpty else { return }

        print("")
        print("Invalidating caches on the mainline server (\(server.serverHostname))...")
        // Stable, readable order.
        let order = [
            "animations", "dialog_scripts", "storyboards", "creatures", "fixtures", "playlists",
        ]
        for collection in order where collections.contains(collection) {
            let (label, result) = await invalidateCache(for: collection)
            switch result {
            case .success(let status):
                print("  \(label) cache invalidated: \(status.message)")
            case .failure(let error):
                print(
                    "  Warning: \(label) cache invalidation failed: "
                        + ServerError.detailedMessage(from: error))
            }
        }
    }

    /// Maps a collection name to the matching `CreatureServerClient` invalidation call.
    private func invalidateCache(for collection: String) async -> (
        String, Result<StatusDTO, ServerError>
    ) {
        switch collection {
        case "animations": return ("animation", await server.invalidateAnimationCache())
        case "dialog_scripts": return ("dialog script", await server.invalidateDialogScriptCache())
        case "storyboards": return ("storyboard", await server.invalidateStoryboardCache())
        case "creatures": return ("creature", await server.invalidateCreatureCache())
        case "fixtures": return ("fixture", await server.invalidateFixtureCache())
        case "playlists": return ("playlist", await server.invalidatePlaylistCache())
        default:
            return (
                collection,
                .failure(.serverError("no cache invalidation available for '\(collection)'"))
            )
        }
    }

    // MARK: - Titles

    private func animationTitle(_ document: Document) -> String {
        if let metadata = document["metadata"] as? Document,
            let title = metadata["title"] as? String,
            !title.isEmpty
        {
            return title
        }
        return (document["id"] as? String) ?? "(untitled)"
    }

    private func titleField(_ document: Document) -> String {
        if let title = document["title"] as? String, !title.isEmpty { return title }
        return (document["id"] as? String) ?? "(untitled)"
    }

    /// Singular, human-readable label for a collection, used in messages.
    private func singular(_ collection: String) -> String {
        switch collection {
        case "animations": return "animation"
        case "dialog_scripts": return "dialog script"
        case "storyboards": return "storyboard"
        case "creatures": return "creature"
        case "fixtures": return "fixture"
        case "playlists": return "playlist"
        default: return collection
        }
    }

    // MARK: - User interaction

    private func confirmIfNeeded() throws {
        guard !assumeYes else { return }
        print(
            "Copy the above into the mainline server (\(mainlineServer))? Type 'yes' to continue: ",
            terminator: "")
        guard let answer = readLine(), answer.lowercased() == "yes" else {
            throw failWithMessage("Back-fill cancelled.")
        }
        print("")
    }

    private func promptForMissing(_ analysis: ContentAnalysis, collection: String) -> MissingChoice
    {
        let copyable = analysis.missing.filter(\.canCopy).count
        let kind = singular(collection)

        print("")
        print(
            "The \(kind) '\(analysis.doc.title)' references items missing on the mainline server:")
        for dependency in analysis.missing {
            let name = dependency.name.map { " (\($0))" } ?? ""
            let status = dependency.canCopy ? "" : " — not found on travel either; cannot copy"
            print(
                "  - \(dependency.reference.kind.label) \(dependency.reference.identifier)\(name)\(status)"
            )
        }

        while true {
            print("What would you like to do?")
            print("  [c] copy the \(kind) anyway (leave references dangling)")
            print("  [d] copy the \(copyable) copyable item(s) from travel, then the \(kind)")
            print("  [s] skip this \(kind)")
            print("  [a] abort the back-fill")
            print("> ", terminator: "")

            switch readLine()?.trimmingCharacters(in: .whitespaces).lowercased().first {
            case "c": return .copyAnyway
            case "d": return .copyDeps
            case "s": return .skip
            case "a": return .abort
            default: print("Please enter c, d, s, or a.")
            }
        }
    }

    // MARK: - Output

    private func printPreview(
        animations: [PlannedDoc], dialogScripts: [ContentAnalysis], storyboards: [ContentAnalysis]
    ) {
        let mode = updateExisting ? "add + update" : "add-only"
        print("")
        print("Back-fill plan (travel \(travelServer) → mainline \(mainlineServer)), \(mode):")
        print("")
        printPlainSection("Animations", animations)
        print("")
        printAnalysisSection("Dialog scripts", dialogScripts)
        print("")
        printAnalysisSection("Storyboards", storyboards)
        print("")
    }

    private func printPlainSection(_ title: String, _ items: [PlannedDoc]) {
        guard !items.isEmpty else {
            print("\(title): none to copy.")
            return
        }
        print("\(title) to copy (\(items.count)):")
        for item in items {
            print("  - \(item.title)\(item.isNew ? "" : " [update]")")
        }
    }

    private func printAnalysisSection(_ title: String, _ analyses: [ContentAnalysis]) {
        guard !analyses.isEmpty else {
            print("\(title): none to copy.")
            return
        }
        print("\(title) to copy (\(analyses.count)):")
        for analysis in analyses {
            print("  - \(analysis.doc.title)\(analysis.doc.isNew ? "" : " [update]")")
            for dependency in analysis.missing {
                let name = dependency.name.map { " (\($0))" } ?? ""
                let status = dependency.canCopy ? "missing" : "missing, dangling on travel"
                print(
                    "      ↳ \(status): \(dependency.reference.kind.label) \(dependency.reference.identifier)\(name)"
                )
            }
            if !analysis.unverifiableSounds.isEmpty {
                print(
                    "      ↳ references sound file(s) (can't verify — files on disk): "
                        + analysis.unverifiableSounds.joined(separator: ", "))
            }
        }
    }

    private func printSummary(
        animations: ApplyResult, dialogScripts: ApplyResult, storyboards: ApplyResult
    ) {
        var parts: [String] = []
        func describe(_ name: String, _ result: ApplyResult) {
            if result.added > 0 { parts.append("\(result.added) \(name)(s) added") }
            if result.updated > 0 { parts.append("\(result.updated) \(name)(s) updated") }
            if result.skipped > 0 { parts.append("\(result.skipped) \(name)(s) skipped") }
        }
        describe("animation", animations)
        describe("dialog script", dialogScripts)
        describe("storyboard", storyboards)

        let dependenciesCopied =
            animations.dependenciesCopied + dialogScripts.dependenciesCopied
            + storyboards.dependenciesCopied
        if dependenciesCopied > 0 {
            parts.append("\(dependenciesCopied) dependency item(s) copied")
        }
        if parts.isEmpty { parts.append("nothing changed") }

        print("")
        print("Done! Back-filled into \(mainlineServer): " + parts.joined(separator: ", ") + ".")
    }
}
