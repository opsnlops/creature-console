import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

@Suite("Character delivery stage")
struct CharacterDeliveryTests {
    @Test("Unknown presence keeps Beaky on the private Communicator stage")
    func unknownPresenceRoutesPrivately() async throws {
        let clock = ManualWorldClock(now: Date(timeIntervalSince1970: 1_789_100_000))
        let repository = InMemoryDeliveryRepository()
        let physical = RecordingSink(state: .performed)
        let communicator = RecordingSink(state: .accepted)
        let router = try CharacterDeliveryRouter(
            presenceProvider: UnknownPresenceProvider(clock: clock),
            repository: repository,
            physicalSpeechSink: physical,
            communicatorSink: communicator,
            clock: clock
        )

        let result = try await router.route(makeIntent())
        let stored = try #require(await repository.stored.values.first)

        #expect(result.disposition == .accepted)
        #expect(result.outcome.route == .communicator)
        #expect(result.outcome.state == .accepted)
        #expect(result.conversationItem == stored.conversationItem)
        #expect(stored.decision.privacyMode == .private)
        #expect(stored.decision.reason == .presenceUncertain)
        #expect(stored.decision.presence.state == .unknown)
        #expect(stored.decision.presence.confidence == 0)
        #expect(stored.decision.presence.provenance.isEmpty)
        #expect(stored.conversationItem.authorKind == .character)
        #expect(await physical.deliveries == 0)
        #expect(await communicator.deliveries == 1)
    }

    @Test("An assumed presence puts Beaky in the room and says it was assumed")
    func assumedPresencePutsBeakyInTheRoom() async throws {
        let clock = ManualWorldClock(now: Date(timeIntervalSince1970: 1_789_100_000))
        let april = try EntityID(validating: "person:april")
        let configuration = PresenceConfiguration(
            assumed: [
                april: try PresenceConfiguration.AssumedPresence(
                    state: .home, physicallyAudible: true, confidence: 0.9)
            ]
        )
        let provider = AssumedPresenceProvider(configuration: configuration, clock: clock)
        let repository = InMemoryDeliveryRepository()
        let router = try CharacterDeliveryRouter(
            presenceProvider: provider,
            repository: repository,
            physicalSpeechSink: RecordingSink(state: .performed),
            communicatorSink: RecordingSink(state: .accepted),
            clock: clock
        )

        let stage = try await router.stage(
            CharacterStageRequest(
                responseID: makeIntent().responseID,
                characterID: makeIntent().characterID,
                recipientID: april
            ),
            in: makeIntent().conversationID
        )
        let stranger = try await provider.presence(for: EntityID(validating: "person:mango"))

        #expect(stage.disposition == .decided)
        #expect(stage.decision.route == .physicalSpeech)
        #expect(stage.decision.reason == .homeAndAudible)
        #expect(stage.decision.presence.basis == .assumed)
        #expect(stage.decision.presence.confidence == 0.9)
        #expect(stranger.state == .unknown)
        #expect(stranger.basis == .inferred)
    }

    @Test("Presence assumptions are read from the world configuration")
    func presenceConfigurationIsParsed() throws {
        let json = """
            {
              "presence": {
                "assumed": {
                  "person:april": { "state": "home", "physically_audible": true, "confidence": 0.9 }
                }
              }
            }
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "creature-world-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = try CreatureWorldConfiguration.load(from: url, environment: [:])
        let april = try EntityID(validating: "person:april")

        #expect(configuration.presence.assumed[april]?.state == .home)
        #expect(configuration.presence.assumed[april]?.physicallyAudible == true)
        #expect(configuration.presence.assumed[april]?.confidence == 0.9)
        #expect(try CreatureWorldConfiguration().presence.assumed.isEmpty)
    }

    @Test("The unconnected physical stage records failure instead of losing the turn")
    func physicalPlaceholderRecordsFailure() async throws {
        let intent = try makeIntent()
        let now = Date(timeIntervalSince1970: 1_789_100_000)
        let decision = try CharacterDeliveryDecision(
            responseID: intent.responseID,
            route: .physicalSpeech,
            privacyMode: .notApplicable,
            reason: .homeAndAudible,
            decidedAt: now,
            presence: PersonPresence(
                personID: intent.recipientID,
                state: .home,
                confidence: 1,
                observedAt: now,
                validUntil: now.addingTimeInterval(60),
                physicallyAudible: true
            )
        )

        let result = try await NotConnectedPhysicalSpeechSink(
            logger: Logger(label: "character-delivery-tests")
        ).deliver(intent, decision: decision)

        #expect(result.state == .failed)
        #expect(result.errorCode == NotConnectedPhysicalSpeechSink.errorCode)
        #expect(result.providerReference == nil)
    }

    @Test("Character response results use the snake_case wire contract")
    func responseResultRoundTripsFixture() throws {
        let data = try Data(contentsOf: fixtureURL)
        let decoded = try WorldJSON.makeDecoder().decode(CharacterDeliveryResult.self, from: data)
        let encoded = try WorldJSON.makeEncoder().encode(decoded)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(decoded.conversationItem.authorKind == .character)
        #expect(decoded.outcome.route == .communicator)
        #expect(Set(json.keys) == ["disposition", "outcome", "conversation_item"])
        #expect(
            try WorldJSON.makeDecoder().decode(CharacterDeliveryResult.self, from: encoded)
                == decoded
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CreatureWorld/character-delivery-result-v1.json")
    }

    private func makeIntent() throws -> CharacterUtteranceIntent {
        try CharacterUtteranceIntent(
            responseID: ResponseID(validating: "response:delivery-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april"),
            text: "April! I can finally say something.",
            urgency: 0.5,
            createdAt: Date(timeIntervalSince1970: 1_789_100_000)
        )
    }
}

private actor InMemoryDeliveryRepository: CharacterDeliveryRepository {
    private(set) var stored: [ResponseID: StoredCharacterDelivery] = [:]

    func delivery(for responseID: ResponseID) -> StoredCharacterDelivery? {
        stored[responseID]
    }

    func prepare(_ delivery: StoredCharacterDelivery) -> StoredCharacterDelivery {
        if let existing = stored[delivery.intent.responseID] {
            return existing
        }
        stored[delivery.intent.responseID] = delivery
        return delivery
    }

    func record(_ outcome: CharacterDeliveryOutcome) {
        stored[outcome.responseID]?.outcome = outcome
    }

    private var stages: [ResponseID: StoredStageDecision] = [:]

    func stageDecision(for responseID: ResponseID) -> StoredStageDecision? {
        stages[responseID]
    }

    func prepareStage(_ stage: StoredStageDecision) -> StoredStageDecision {
        if let existing = stages[stage.decision.responseID] {
            return existing
        }
        stages[stage.decision.responseID] = stage
        return stage
    }
}

private actor RecordingSink: CharacterDeliverySink {
    private let state: CharacterDeliveryOutcomeState
    private(set) var deliveries = 0

    init(state: CharacterDeliveryOutcomeState) {
        self.state = state
    }

    func deliver(
        _ intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) -> DeliverySinkResult {
        deliveries += 1
        return DeliverySinkResult(state: state)
    }
}
