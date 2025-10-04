import Foundation
import SwiftData

/// Concurrency-safe holder for the app's single SwiftData ModelContainer.
/// Set this once at app launch and use via `await SoundDataStore.shared.container()`.
actor SoundDataStore {
    static let shared = SoundDataStore()

    private var stored: ModelContainer?

    func setContainer(_ container: ModelContainer) {
        self.stored = container
    }

    /// Returns the shared ModelContainer. Crashes if not set; set during app launch.
    func container() -> ModelContainer {
        guard let c = stored else {
            fatalError("SoundDataStore.container() accessed before being set")
        }
        return c
    }

    /// Creates and returns a ModelContainer for SoundModel with retry logic.
    /// On failure, attempts to delete the store directory and retry once.
    static func createModelContainer() throws -> ModelContainer {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let storeURL = appSupport.appendingPathComponent("SoundStore", isDirectory: true)

        do {
            let config = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: SoundModel.self, configurations: config)
        } catch {
            // Remove the store directory and retry once
            if fm.fileExists(atPath: storeURL.path) {
                try? fm.removeItem(at: storeURL)
            }
            let config = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: SoundModel.self, configurations: config)
        }
    }
}
