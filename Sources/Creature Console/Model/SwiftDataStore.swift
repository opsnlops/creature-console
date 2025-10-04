import Foundation
import SwiftData

/// Shared concurrency-safe holder for the app's SwiftData ModelContainer.
/// This eliminates duplication across individual data store actors.
actor SwiftDataStore {
    static let shared = SwiftDataStore()

    private var stored: ModelContainer?

    func setContainer(_ container: ModelContainer) {
        self.stored = container
    }

    /// Returns the shared ModelContainer. Crashes if not set; set during app launch.
    func container() -> ModelContainer {
        guard let c = stored else {
            fatalError("SwiftDataStore.container() accessed before being set")
        }
        return c
    }
}
