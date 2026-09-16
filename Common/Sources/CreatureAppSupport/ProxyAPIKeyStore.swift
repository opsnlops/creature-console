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

        sharedBackend = KeychainBackend(
            accessGroup: normalizedAccessGroup, service: CreatureAppFamily.proxyKeychainService,
            account: CreatureAppFamily.proxyAPIKeyAccount)
        legacyBackend =
            migrateLegacyConsoleKey
            ? KeychainBackend(
                accessGroup: nil, service: CreatureAppFamily.proxyKeychainService,
                account: CreatureAppFamily.proxyAPIKeyAccount) : nil
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

/// One secret in the Creature app family's shared Keychain, by service and account -
/// synchronizable, so a password typed on one Mac is there on the next. The proxy API key is
/// one such item; an IMAP password is another.
public struct CreatureKeychainItem: Sendable {
    private let backend: KeychainBackend

    /// The item in the shared access group the app declares in its Info.plist.
    public init(service: String, account: String, bundle: Bundle = .main) throws {
        guard
            let accessGroup = bundle.object(
                forInfoDictionaryKey: CreatureAppFamily.sharedKeychainAccessGroupInfoKey
            ) as? String, !accessGroup.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw ProxyAPIKeyStoreError.missingSharedAccessGroup
        }
        backend = KeychainBackend(accessGroup: accessGroup, service: service, account: account)
    }

    public func value() throws -> String? { try backend.value() }
    public func set(_ value: String?) throws { try backend.set(value) }

    /// The Keychain refuses to hand over an item while the Mac is locked unless the item says
    /// otherwise; an app that works while April is out (the Bridge reading mail) needs
    /// otherwise. Idempotent; nothing to do when the item is absent.
    public func allowReadingWhileLocked() throws { try backend.allowReadingWhileLocked() }
}

extension ProxyAPIKeyStoreError {
    /// The Keychain said no because the Mac is locked - a passing condition, not a missing item.
    public var isMacLocked: Bool {
        if case .keychainFailure(let status) = self { return status == errSecInteractionNotAllowed }
        return false
    }
}

struct KeychainBackend: ProxyAPIKeyBacking, Sendable {
    let accessGroup: String?
    let service: String
    let account: String

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
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let update: [String: Any] = [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]
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

    func allowReadingWhileLocked() throws {
        let update = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProxyAPIKeyStoreError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
