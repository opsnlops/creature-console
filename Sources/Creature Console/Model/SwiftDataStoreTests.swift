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
