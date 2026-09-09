import Foundation

public enum WorldIdentifierError: Error, Equatable, Sendable {
    case invalidEventID(String)
    case invalidNamespacedID(String)
    case unexpectedNamespace(expected: String, actual: String)
}

public protocol NamespacedIDDomain: Sendable {
    static var requiredNamespace: String? { get }
}

public protocol FixedNamespaceIDDomain: NamespacedIDDomain {
    static var namespace: String { get }
}

extension FixedNamespaceIDDomain {
    public static var requiredNamespace: String? { namespace }
}

public struct NamespacedID<Domain: NamespacedIDDomain>: RawRepresentable, Hashable, Sendable,
    Codable, CustomStringConvertible
{
    public let rawValue: String

    private init(uncheckedRawValue: String) {
        self.rawValue = uncheckedRawValue
    }

    public init(validating rawValue: String) throws {
        let components = rawValue.split(
            separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2,
            Self.isValidNamespace(components[0]),
            Self.isValidValue(components[1])
        else {
            throw WorldIdentifierError.invalidNamespacedID(rawValue)
        }

        if let expected = Domain.requiredNamespace, components[0] != Substring(expected) {
            throw WorldIdentifierError.unexpectedNamespace(
                expected: expected,
                actual: String(components[0])
            )
        }
        self.rawValue = rawValue
    }

    public init?(rawValue: String) {
        try? self.init(validating: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValidNamespace(_ namespace: Substring) -> Bool {
        guard let first = namespace.utf8.first, first >= 97, first <= 122 else { return false }
        return namespace.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
        }
    }

    private static func isValidValue(_ value: Substring) -> Bool {
        guard !value.isEmpty else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
                || byte == 46 || byte == 58 || byte == 95
        }
    }

    private static func generated(namespace: String, using uuid: UUID) -> Self {
        Self(uncheckedRawValue: "\(namespace):\(uuid.uuidString.lowercased())")
    }
}

public enum EntityIDDomain: NamespacedIDDomain {
    public static let requiredNamespace: String? = nil
}

public enum SourceIDDomain: NamespacedIDDomain {
    public static let requiredNamespace: String? = nil
}

public enum FactIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "fact"
}

public enum TimerIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "timer"
}

public enum ConsiderationIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "consideration"
}

public enum MemoryIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "memory"
}

public enum IntentIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "intent"
}

public enum InteractionIDDomain: FixedNamespaceIDDomain {
    public static let namespace = "interaction"
}

public typealias EntityID = NamespacedID<EntityIDDomain>
public typealias SourceID = NamespacedID<SourceIDDomain>
public typealias FactID = NamespacedID<FactIDDomain>
public typealias TimerID = NamespacedID<TimerIDDomain>
public typealias ConsiderationID = NamespacedID<ConsiderationIDDomain>
public typealias MemoryID = NamespacedID<MemoryIDDomain>
public typealias IntentID = NamespacedID<IntentIDDomain>
public typealias InteractionID = NamespacedID<InteractionIDDomain>

extension NamespacedID where Domain == FactIDDomain {
    public static func generated(using uuid: UUID = UUID()) -> Self {
        generated(namespace: FactIDDomain.namespace, using: uuid)
    }
}

extension NamespacedID where Domain == TimerIDDomain {
    /// Creates a timer identifier from a stable semantic key such as
    /// `calendar-event-123:departure-due`.
    public static func stable(_ key: String) throws -> Self {
        try Self(validating: "\(TimerIDDomain.namespace):\(key)")
    }
}

extension NamespacedID where Domain == ConsiderationIDDomain {
    public static func generated(using uuid: UUID = UUID()) -> Self {
        generated(namespace: ConsiderationIDDomain.namespace, using: uuid)
    }
}

extension NamespacedID where Domain == MemoryIDDomain {
    public static func generated(using uuid: UUID = UUID()) -> Self {
        generated(namespace: MemoryIDDomain.namespace, using: uuid)
    }
}

extension NamespacedID where Domain == IntentIDDomain {
    public static func generated(using uuid: UUID = UUID()) -> Self {
        generated(namespace: IntentIDDomain.namespace, using: uuid)
    }
}

extension NamespacedID where Domain == InteractionIDDomain {
    public static func generated(using uuid: UUID = UUID()) -> Self {
        generated(namespace: InteractionIDDomain.namespace, using: uuid)
    }
}

public struct EventID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    private init(uncheckedRawValue: String) {
        self.rawValue = uncheckedRawValue
    }

    public init(validating rawValue: String) throws {
        guard Self.hasCanonicalShape(rawValue), let uuid = UUID(uuidString: rawValue) else {
            throw WorldIdentifierError.invalidEventID(rawValue)
        }
        self.rawValue = uuid.uuidString.lowercased()
    }

    public init?(rawValue: String) {
        try? self.init(validating: rawValue)
    }

    public static func generated(using uuid: UUID = UUID()) -> Self {
        Self(uncheckedRawValue: uuid.uuidString.lowercased())
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func hasCanonicalShape(_ value: String) -> Bool {
        guard value.utf8.count == 36 else { return false }
        for (index, byte) in value.utf8.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == 45 else { return false }
            } else {
                let isDigit = byte >= 48 && byte <= 57
                let isLowerHex = byte >= 97 && byte <= 102
                let isUpperHex = byte >= 65 && byte <= 70
                guard isDigit || isLowerHex || isUpperHex else { return false }
            }
        }
        return true
    }
}
