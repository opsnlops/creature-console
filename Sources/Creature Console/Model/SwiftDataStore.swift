import Foundation
import SwiftData

/// Shared concurrency-safe holder for the app's SwiftData ModelContainer.
///
/// The container is created during `CreatureConsole.init` and handed in via a
/// fire-and-forget `Task` (init can't await — it's synchronous). Callers asking for
/// the container before that Task has run get parked on a continuation and resume
/// the moment `setContainer` lands, rather than crashing the app.
actor SwiftDataStore {
    static let shared = SwiftDataStore()

    private var stored: ModelContainer?
    private var waiters: [CheckedContinuation<ModelContainer, Never>] = []

    func setContainer(_ container: ModelContainer) {
        self.stored = container
        let toResume = waiters
        waiters.removeAll()
        for waiter in toResume {
            waiter.resume(returning: container)
        }
    }

    /// Returns the shared ModelContainer, awaiting `setContainer` if it hasn't
    /// happened yet. Callers should `await` this.
    func container() async -> ModelContainer {
        if let c = stored { return c }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// Schema-versioning for the on-disk SwiftData store, shared by the macOS/iOS and tvOS apps.
///
/// The store is a disposable cache of server data, so we never need to *preserve* it across
/// a schema change — we only need to avoid opening a half-migrated one. SwiftData's
/// lightweight migration handles compatible property changes, and incompatible ones throw
/// (callers recover by wiping). But *removing* a `@Model` does neither: SwiftData opens the
/// store anyway and logs `Persistent History … has to be truncated … entities being removed`,
/// leaving a degraded store that the usual try/catch never sees. That's what forced a manual
/// cache wipe when the `InputModel` entity was removed.
///
/// To make every structural change (add / remove / rename a model) self-healing, we fingerprint
/// the model set and stash it next to the store. When the fingerprint changes we wipe the store
/// before opening it; the app then repopulates from the server on launch.
enum SwiftDataStoreMigration {

    /// A deterministic signature of the current model set (module-qualified type names, sorted
    /// so ordering changes don't trigger a wipe).
    static func signature(for modelTypes: [any PersistentModel.Type]) -> String {
        modelTypes.map { String(reflecting: $0) }.sorted().joined(separator: "\n")
    }

    /// Sidecar file that records the model-set signature the store was last opened with.
    static func signatureURL(for storeURL: URL) -> URL {
        storeURL.deletingPathExtension().appendingPathExtension("schema")
    }

    /// Returns the signature persisted alongside the store, if any.
    static func storedSignature(for storeURL: URL) -> String? {
        try? String(contentsOf: signatureURL(for: storeURL), encoding: .utf8)
    }

    /// True when the on-disk store predates a structural schema change and should be wiped
    /// before opening.
    static func needsWipe(storeURL: URL, modelTypes: [any PersistentModel.Type]) -> Bool {
        storedSignature(for: storeURL) != signature(for: modelTypes)
    }

    /// Records the current model-set signature after a successful open.
    static func recordSignature(storeURL: URL, modelTypes: [any PersistentModel.Type]) {
        try? signature(for: modelTypes).write(
            to: signatureURL(for: storeURL), atomically: true, encoding: .utf8)
    }
}
