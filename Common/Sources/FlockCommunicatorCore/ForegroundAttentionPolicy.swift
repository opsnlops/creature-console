import Foundation

public enum CommunicatorPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

public struct ForegroundAttentionEvidence: Equatable, Sendable {
    public var platform: CommunicatorPlatform
    public var sceneIsActive: Bool
    public var deviceIsUnlocked: Bool
    public var appAppearsActive: Bool
    public var conversationWindowIsVisible: Bool
    public var conversationWindowIsMinimized: Bool
    public var systemIdleDuration: TimeInterval

    public init(
        platform: CommunicatorPlatform,
        sceneIsActive: Bool,
        deviceIsUnlocked: Bool = true,
        appAppearsActive: Bool = true,
        conversationWindowIsVisible: Bool = true,
        conversationWindowIsMinimized: Bool = false,
        systemIdleDuration: TimeInterval = 0
    ) {
        self.platform = platform
        self.sceneIsActive = sceneIsActive
        self.deviceIsUnlocked = deviceIsUnlocked
        self.appAppearsActive = appAppearsActive
        self.conversationWindowIsVisible = conversationWindowIsVisible
        self.conversationWindowIsMinimized = conversationWindowIsMinimized
        self.systemIdleDuration = systemIdleDuration
    }
}

public enum ForegroundAttentionPolicyError: Error, Equatable, Sendable {
    case invalidMaximumIdleDuration
}

/// Reduces platform lifecycle and local input evidence to the one privacy-preserving fact the
/// gateway needs: whether this installation should currently hold a foreground lease.
public struct ForegroundAttentionPolicy: Equatable, Sendable {
    public static let standard = ForegroundAttentionPolicy(validatedMaximumMacIdleDuration: 300)

    public var maximumMacIdleDuration: TimeInterval

    public init(maximumMacIdleDuration: TimeInterval) throws {
        guard maximumMacIdleDuration.isFinite, maximumMacIdleDuration > 0 else {
            throw ForegroundAttentionPolicyError.invalidMaximumIdleDuration
        }
        self.maximumMacIdleDuration = maximumMacIdleDuration
    }

    private init(validatedMaximumMacIdleDuration: TimeInterval) {
        maximumMacIdleDuration = validatedMaximumMacIdleDuration
    }

    public func isAttentive(_ evidence: ForegroundAttentionEvidence) -> Bool {
        guard evidence.sceneIsActive, evidence.deviceIsUnlocked else { return false }
        switch evidence.platform {
        case .iOS:
            return true
        case .macOS:
            return evidence.appAppearsActive
                && evidence.conversationWindowIsVisible
                && !evidence.conversationWindowIsMinimized
                && evidence.systemIdleDuration.isFinite
                && evidence.systemIdleDuration < maximumMacIdleDuration
        }
    }
}
