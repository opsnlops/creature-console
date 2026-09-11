import Foundation
@preconcurrency import Security

public enum ProxyAPIKeyStoreError: LocalizedError, Equatable {
    case missingSharedAccessGroup
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingSharedAccessGroup:
            "The app is missing its shared Creature Keychain access-group configuration"
        case .keychainFailure(let status):
            "Keychain operation failed with status \(status)"
        }
    }
}

/// Main-actor ownership for the API key shared by the Creature app family.
///
/// The Console may provide its legacy private access group as a migration source. Reads then copy
/// the existing key into the shared group, and writes mirror it for rollback compatibility.
@MainActor
public final class ProxyAPIKeyStore {
    private let sharedBackend: any ProxyAPIKeyBacking
    private let legacyBackend: (any ProxyAPIKeyBacking)?

    public init(
        accessGroup: String,
        migrateLegacyConsoleKey: Bool = false
    ) throws {
        let normalizedAccessGroup = accessGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccessGroup.isEmpty else {
            throw ProxyAPIKeyStoreError.missingSharedAccessGroup
        }

        sharedBackend = KeychainBackend(accessGroup: normalizedAccessGroup)
        legacyBackend = migrateLegacyConsoleKey ? KeychainBackend(accessGroup: nil) : nil
    }

    init(
        sharedBackend: any ProxyAPIKeyBacking,
        legacyBackend: (any ProxyAPIKeyBacking)?
    ) {
        self.sharedBackend = sharedBackend
        self.legacyBackend = legacyBackend
    }

    public convenience init(
        bundle: Bundle = .main,
        migrateLegacyConsoleKey: Bool = false
    ) throws {
        guard
            let accessGroup = bundle.object(
                forInfoDictionaryKey: CreatureAppFamily.sharedKeychainAccessGroupInfoKey
            ) as? String
        else {
            throw ProxyAPIKeyStoreError.missingSharedAccessGroup
        }
        try self.init(
            accessGroup: accessGroup,
            migrateLegacyConsoleKey: migrateLegacyConsoleKey
        )
    }

    public func apiKey() throws -> String? {
        if let sharedValue = try sharedBackend.value() {
            return sharedValue
        }
        guard let legacyValue = try legacyBackend?.value() else { return nil }
        try sharedBackend.set(legacyValue)
        return legacyValue
    }

    public func setAPIKey(_ value: String?) throws {
        let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedValue = normalizedValue?.isEmpty == false ? normalizedValue : nil
        try sharedBackend.set(storedValue)
        try legacyBackend?.set(storedValue)
    }
}

protocol ProxyAPIKeyBacking {
    func value() throws -> String?
    func set(_ value: String?) throws
}

private struct KeychainBackend: ProxyAPIKeyBacking {
    let accessGroup: String?

    func value() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ProxyAPIKeyStoreError.keychainFailure(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ProxyAPIKeyStoreError.keychainFailure(errSecDecode)
        }
        return value
    }

    func set(_ value: String?) throws {
        if let value {
            let data = Data(value.utf8)
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let update = [kSecValueData as String: data]
                let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
                guard updateStatus == errSecSuccess else {
                    throw ProxyAPIKeyStoreError.keychainFailure(updateStatus)
                }
            } else if status != errSecSuccess {
                throw ProxyAPIKeyStoreError.keychainFailure(status)
            }
        } else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw ProxyAPIKeyStoreError.keychainFailure(status)
            }
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CreatureAppFamily.proxyKeychainService,
            kSecAttrAccount as String: CreatureAppFamily.proxyAPIKeyAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
