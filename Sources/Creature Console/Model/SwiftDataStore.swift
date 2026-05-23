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
