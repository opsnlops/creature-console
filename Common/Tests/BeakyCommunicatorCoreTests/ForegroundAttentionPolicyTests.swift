import BeakyCommunicatorCore
import Testing

@Suite("Communicator foreground attention policy")
struct ForegroundAttentionPolicyTests {
    @Test("Only an active iOS scene is attentive")
    func iOSAttention() {
        let policy = ForegroundAttentionPolicy.standard

        #expect(
            policy.isAttentive(
                ForegroundAttentionEvidence(platform: .iOS, sceneIsActive: true)
            )
        )
        #expect(
            !policy.isAttentive(
                ForegroundAttentionEvidence(platform: .iOS, sceneIsActive: false)
            )
        )
        #expect(
            !policy.isAttentive(
                ForegroundAttentionEvidence(
                    platform: .iOS,
                    sceneIsActive: true,
                    deviceIsUnlocked: false
                )
            )
        )
    }

    @Test("A locked Mac is never attentive")
    func macOSLockState() {
        let evidence = ForegroundAttentionEvidence(
            platform: .macOS,
            sceneIsActive: true,
            deviceIsUnlocked: false
        )

        #expect(!ForegroundAttentionPolicy.standard.isAttentive(evidence))
    }

    @Test("macOS requires an active visible non-minimized conversation window")
    func macOSWindowAttention() {
        let policy = ForegroundAttentionPolicy.standard
        let attentive = ForegroundAttentionEvidence(platform: .macOS, sceneIsActive: true)
        #expect(policy.isAttentive(attentive))

        var inactiveApp = attentive
        inactiveApp.appAppearsActive = false
        #expect(!policy.isAttentive(inactiveApp))

        var hiddenWindow = attentive
        hiddenWindow.conversationWindowIsVisible = false
        #expect(!policy.isAttentive(hiddenWindow))

        var minimizedWindow = attentive
        minimizedWindow.conversationWindowIsMinimized = true
        #expect(!policy.isAttentive(minimizedWindow))
    }

    @Test("An idle Mac stops being attentive at the configured boundary")
    func macOSIdleBoundary() throws {
        let policy = try ForegroundAttentionPolicy(maximumMacIdleDuration: 120)

        #expect(
            policy.isAttentive(
                ForegroundAttentionEvidence(
                    platform: .macOS,
                    sceneIsActive: true,
                    systemIdleDuration: 119.999
                )
            )
        )
        #expect(
            !policy.isAttentive(
                ForegroundAttentionEvidence(
                    platform: .macOS,
                    sceneIsActive: true,
                    systemIdleDuration: 120
                )
            )
        )
    }

    @Test("Invalid idle thresholds are rejected")
    func invalidIdleThreshold() {
        #expect(throws: ForegroundAttentionPolicyError.invalidMaximumIdleDuration) {
            try ForegroundAttentionPolicy(maximumMacIdleDuration: 0)
        }
        #expect(throws: ForegroundAttentionPolicyError.invalidMaximumIdleDuration) {
            try ForegroundAttentionPolicy(maximumMacIdleDuration: .infinity)
        }
    }
}
