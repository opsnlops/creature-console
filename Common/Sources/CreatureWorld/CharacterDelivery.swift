import Foundation
import Logging
import WorldCore

/// Reports that the world does not yet know where a person is.
///
/// No presence source is connected until the Home Assistant adapter (VW-013) and the first presence
/// reducer (VW-006) land. Rather than fabricate confidence, this provider returns `unknown` with zero
/// confidence and no validity window, which makes `CharacterDeliveryRouter` choose the private
/// Communicator route with reason `presence_uncertain`. Swapping in a real provider changes nothing
/// downstream.
struct UnknownPresenceProvider: PersonPresenceProviding, Sendable {
    private let clock: any WorldClock

    init(clock: any WorldClock) {
        self.clock = clock
    }

    func presence(for personID: EntityID) async throws -> PersonPresence {
        let now = await clock.now
        return try PersonPresence(
            personID: personID,
            state: .unknown,
            confidence: 0,
            observedAt: now,
            validUntil: now,
            physicallyAudible: false
        )
    }
}

/// Reports a configured assumption about where a person is, as an assumption.
///
/// Until a presence source exists, "April is home and audible" is the honest default that lets
/// Beaky answer in the room. The presence carries `basis: assumed` so every routing decision
/// records that it rested on configuration, not evidence. People without an assumption are
/// `unknown`, exactly as `UnknownPresenceProvider` reports them.
struct AssumedPresenceProvider: PersonPresenceProviding, Sendable {
    /// An assumption holds for as long as it is configured; each reading is fresh for a short
    /// window so a decision made a moment later still sees it as current.
    static let validity: TimeInterval = 60

    private let assumptions: [EntityID: PresenceConfiguration.AssumedPresence]
    private let unknown: UnknownPresenceProvider
    private let clock: any WorldClock

    init(configuration: PresenceConfiguration, clock: any WorldClock) {
        assumptions = configuration.assumed
        unknown = UnknownPresenceProvider(clock: clock)
        self.clock = clock
    }

    func presence(for personID: EntityID) async throws -> PersonPresence {
        guard let assumption = assumptions[personID] else {
            return try await unknown.presence(for: personID)
        }
        let now = await clock.now
        return try PersonPresence(
            personID: personID,
            state: assumption.state,
            confidence: assumption.confidence,
            observedAt: now,
            validUntil: now.addingTimeInterval(Self.validity),
            physicallyAudible: assumption.physicallyAudible,
            basis: .assumed
        )
    }
}

/// Durable Communicator delivery.
///
/// By the time a sink runs, the router has already persisted Beaky's canonical conversation item,
/// and the persistence provider publishes it to every live conversation subscriber. Durable app
/// delivery is therefore satisfied by the item's existence; `performed` stays reserved for a real
/// open, acknowledgement, or reply so the world never claims April saw something she did not.
struct CommunicatorDeliverySink: CharacterDeliverySink, Sendable {
    func deliver(
        _ intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) async throws -> DeliverySinkResult {
        DeliverySinkResult(state: .accepted)
    }
}

/// Placeholder for the Creature Server stage until VW-016 connects the ad-hoc speech client.
///
/// The router only chooses physical speech when presence says April is confidently home and
/// audible, which no presence source can claim yet. If that ever happens before the real sink
/// exists, the turn is recorded as failed instead of throwing, so it stays durable and visible in
/// Communicator history rather than being retried forever.
struct NotConnectedPhysicalSpeechSink: CharacterDeliverySink, Sendable {
    static let errorCode = "physical_speech_not_connected"

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func deliver(
        _ intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) async throws -> DeliverySinkResult {
        logger.warning(
            "Physical speech was chosen but no Creature Server sink is connected",
            metadata: [
                "conversation.response.id": "\(intent.responseID.rawValue)",
                "conversation.delivery.attempt.id": "\(decision.attemptID.rawValue)",
            ]
        )
        return DeliverySinkResult(state: .failed, errorCode: Self.errorCode)
    }
}
