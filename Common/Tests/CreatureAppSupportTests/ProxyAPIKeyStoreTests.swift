import Testing

@testable import CreatureAppSupport

@MainActor
@Suite("Shared proxy API key store")
struct ProxyAPIKeyStoreTests {
    @Test("Legacy Console key migrates into the app-family access group")
    func migratesLegacyKey() throws {
        let shared = MemoryProxyAPIKeyBacking()
        let legacy = MemoryProxyAPIKeyBacking(value: "existing-key")
        let store = ProxyAPIKeyStore(sharedBackend: shared, legacyBackend: legacy)

        #expect(try store.apiKey() == "existing-key")
        #expect(shared.storedValue == "existing-key")
    }

    @Test("Shared key wins over a legacy value")
    func sharedKeyWins() throws {
        let shared = MemoryProxyAPIKeyBacking(value: "shared-key")
        let legacy = MemoryProxyAPIKeyBacking(value: "old-key")
        let store = ProxyAPIKeyStore(sharedBackend: shared, legacyBackend: legacy)

        #expect(try store.apiKey() == "shared-key")
        #expect(legacy.storedValue == "old-key")
    }

    @Test("Console-compatible writes update shared and legacy storage")
    func mirrorsWrites() throws {
        let shared = MemoryProxyAPIKeyBacking()
        let legacy = MemoryProxyAPIKeyBacking(value: "old-key")
        let store = ProxyAPIKeyStore(sharedBackend: shared, legacyBackend: legacy)

        try store.setAPIKey(" new-key ")

        #expect(shared.storedValue == "new-key")
        #expect(legacy.storedValue == "new-key")

        try store.setAPIKey("   ")
        #expect(shared.storedValue == nil)
        #expect(legacy.storedValue == nil)
    }
}

private final class MemoryProxyAPIKeyBacking: ProxyAPIKeyBacking {
    private(set) var storedValue: String?

    init(value: String? = nil) {
        storedValue = value
    }

    func value() throws -> String? {
        storedValue
    }

    func set(_ value: String?) throws {
        storedValue = value
    }
}
