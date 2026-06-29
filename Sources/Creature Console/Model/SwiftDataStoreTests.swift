import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("SwiftDataStore basics")
struct SwiftDataStoreTests {

    @Test("stores and retrieves container")
    func storesAndRetrievesContainer() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let store = SwiftDataStore()
        await store.setContainer(container)
        let retrieved = await store.container()

        #expect(retrieved === container)
    }

    @Test("different instances share same singleton")
    func differentInstancesShareSingleton() async throws {
        let store1 = SwiftDataStore.shared
        let store2 = SwiftDataStore.shared

        #expect(store1 === store2)
    }
}

@Suite("SwiftDataStoreMigration fingerprinting")
struct SwiftDataStoreMigrationTests {

    @Test("signature is stable and order-independent")
    func signatureStableAndOrderIndependent() {
        let a = SwiftDataStoreMigration.signature(for: [
            SoundModel.self, CreatureModel.self, AnimationMetadataModel.self,
        ])
        let b = SwiftDataStoreMigration.signature(for: [
            AnimationMetadataModel.self, SoundModel.self, CreatureModel.self,
        ])
        #expect(a == b)
    }

    @Test("adding or removing a model changes the signature")
    func structuralChangeChangesSignature() {
        let base = SwiftDataStoreMigration.signature(for: [SoundModel.self, CreatureModel.self])
        let added = SwiftDataStoreMigration.signature(for: [
            SoundModel.self, CreatureModel.self, PlaylistModel.self,
        ])
        let removed = SwiftDataStoreMigration.signature(for: [SoundModel.self])
        #expect(base != added)
        #expect(base != removed)
    }

    @Test("needsWipe is true for a fresh store and false after recording")
    func needsWipeRoundTrip() throws {
        let modelTypes: [any PersistentModel.Type] = [SoundModel.self, CreatureModel.self]
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let storeURL = tmp.appendingPathComponent("Store.sqlite")

        // No sidecar yet → must wipe.
        #expect(SwiftDataStoreMigration.needsWipe(storeURL: storeURL, modelTypes: modelTypes))

        // After recording the current model set, the same set no longer needs a wipe.
        SwiftDataStoreMigration.recordSignature(storeURL: storeURL, modelTypes: modelTypes)
        #expect(!SwiftDataStoreMigration.needsWipe(storeURL: storeURL, modelTypes: modelTypes))

        // A structural change (model removed) must trigger a wipe again.
        #expect(
            SwiftDataStoreMigration.needsWipe(storeURL: storeURL, modelTypes: [SoundModel.self]))
    }
}
