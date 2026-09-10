import Foundation
import Testing

@testable import WorldCore

@Suite("Unified bidirectional conversation pipeline")
struct ConversationServiceTests {
    @Test("Typed, wizard, and future spoken adapters share Beaky's percept path")
    func adaptersShareOnePerceptPath() async throws {
        let adapters: [PersonUtteranceAdapter] = [
            .communicatorComposition,
            .developmentWizard,
            .speechToText,
        ]
        var percepts: [PersonUtterancePercept] = []

        for (index, adapter) in adapters.enumerated() {
            let repository = TestUtteranceRepository(priorItems: [try makePriorItem()])
            let sink = TestPerceptSink()
            let service = PersonUtteranceIngressService(
                repository: repository,
                sink: sink,
                makeConsiderationID: {
                    try! ConsiderationID(validating: "consideration:shared-semantic-turn")
                },
                makeConversationItemID: {
                    try! ConversationItemID(validating: "conversation-item:april-turn")
                }
            )
            let input = try makeAdapterInput(
                sourceID: SourceID(validating: "adapter:source-\(index)")
            )

            let result = try await adapter.submit(
                input,
                context: UtteranceIngressContext(boundary: .trustedLAN),
                to: service
            )
            #expect(result.disposition == .accepted)
            percepts.append(try #require(await sink.percepts.first))
        }

        let semanticInputs = percepts.map(SemanticPercept.init)
        #expect(Set(semanticInputs).count == 1)
        #expect(
            percepts.map(\.utterance.source) == [
                .communicatorComposition, .developmentWizard, .speechToText,
            ])
        #expect(percepts.map(\.utterance.modality) == [.typed, .typed, .spoken])
    }

    @Test("April's ordered turns build the conversation context Beaky hears")
    func orderedTurnsBuildConversationContext() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = PersonUtteranceIngressService(repository: repository, sink: sink)
        let first = try makeAdapterInput(sourceID: SourceID(validating: "wizard:development"))
        var second = first
        second.utteranceID = try UtteranceID(validating: "utterance:april-2")
        second.text = "I am answering because what you say matters to me."
        second.occurredAt = first.occurredAt.addingTimeInterval(1)

        _ = try await PersonUtteranceAdapter.developmentWizard.submit(
            first,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: service
        )
        _ = try await PersonUtteranceAdapter.developmentWizard.submit(
            second,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: service
        )

        let percepts = await sink.percepts
        #expect(percepts.map(\.utterance.utteranceID) == [first.utteranceID, second.utteranceID])
        guard percepts.count == 2 else { return }
        #expect(percepts[0].priorConversationItems.isEmpty)
        #expect(percepts[1].priorConversationItems.map(\.utteranceID) == [first.utteranceID])
        #expect(percepts[1].priorConversationItems[0].text == first.text)
    }

    @Test("A retry after service restart does not make Beaky hear April twice")
    func ingressRetryAcrossRestartIsIdempotent() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:development"))
        let firstService = makeIngressService(repository: repository, sink: sink)

        let first = try await PersonUtteranceAdapter.developmentWizard.submit(
            input,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: firstService
        )
        let restartedService = makeIngressService(repository: repository, sink: sink)
        let duplicate = try await PersonUtteranceAdapter.developmentWizard.submit(
            input,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: restartedService
        )

        #expect(first.disposition == .accepted)
        #expect(duplicate.disposition == .duplicate)
        #expect(duplicate.percept.considerationID == first.percept.considerationID)
        #expect(duplicate.conversationItem.itemID == first.conversationItem.itemID)
        #expect(await sink.submissionCount == 1)
    }

    @Test("An utterance ID cannot be reused to make Beaky hear different words")
    func conflictingUtteranceIdentityIsRejected() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = makeIngressService(repository: repository, sink: sink)
        let original = try makeAdapterInput(sourceID: SourceID(validating: "wizard:development"))
        var conflict = original
        conflict.text = "Different words under the same identity"

        _ = try await PersonUtteranceAdapter.developmentWizard.submit(
            original,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: service
        )
        await #expect(throws: WorldContractError.conflictingConversationIdentity) {
            try await PersonUtteranceAdapter.developmentWizard.submit(
                conflict,
                context: UtteranceIngressContext(boundary: .trustedLAN),
                to: service
            )
        }

        #expect(await sink.submissionCount == 1)
    }

    @Test("A restart after Beaky hears April retries the same percept identity")
    func ingressCheckpointFailureRetriesIdempotently() async throws {
        let repository = TestUtteranceRepository()
        await repository.failNextCheckpoint()
        let sink = TestPerceptSink()
        let input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:development"))
        let firstService = makeIngressService(repository: repository, sink: sink)

        await #expect(throws: TestError.interruptedBeforeCheckpoint) {
            try await PersonUtteranceAdapter.developmentWizard.submit(
                input,
                context: UtteranceIngressContext(boundary: .trustedLAN),
                to: firstService
            )
        }

        let restartedService = makeIngressService(repository: repository, sink: sink)
        let retry = try await PersonUtteranceAdapter.developmentWizard.submit(
            input,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: restartedService
        )

        #expect(retry.disposition == .duplicate)
        #expect(await sink.submissionCount == 1)
        #expect(await repository.progress(for: input.utteranceID) == .perceptSubmitted)
    }

    @Test("Authenticated gateway calls cannot impersonate April")
    func authenticatedGatewayRejectsWrongPrincipal() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = makeIngressService(repository: repository, sink: sink)
        let input = try makeAdapterInput(
            sourceID: SourceID(validating: "communicator:april-iphone")
        )

        await #expect(throws: WorldContractError.unauthorizedUtteranceIngress) {
            try await PersonUtteranceAdapter.communicatorComposition.submit(
                input,
                context: UtteranceIngressContext(
                    boundary: .authenticatedGateway,
                    principalID: try EntityID(validating: "person:someone-else")
                ),
                to: service
            )
        }
        #expect(await repository.preparedCount == 0)
        #expect(await sink.submissionCount == 0)
    }

    @Test(
        "Beaky speaks in the room when April is home and uses Communicator when away or uncertain",
        arguments: [
            RoutingCase(
                state: .home,
                confidence: 0.98,
                validUntilOffset: 60,
                physicallyAudible: true,
                expectedRoute: .physicalSpeech,
                expectedPrivacy: .notApplicable
            ),
            RoutingCase(
                state: .away,
                confidence: 0.98,
                validUntilOffset: 60,
                physicallyAudible: false,
                expectedRoute: .communicator,
                expectedPrivacy: .preview
            ),
            RoutingCase(
                state: .home,
                confidence: 0.98,
                validUntilOffset: -1,
                physicallyAudible: true,
                expectedRoute: .communicator,
                expectedPrivacy: .private
            ),
            RoutingCase(
                state: .unknown,
                confidence: 0.4,
                validUntilOffset: 60,
                physicallyAudible: false,
                expectedRoute: .communicator,
                expectedPrivacy: .private
            ),
        ]
    )
    func routingFollowsFreshPresence(testCase: RoutingCase) async throws {
        let dependencies = try makeRouterDependencies(testCase: testCase)
        let router = try makeRouter(dependencies: dependencies)

        let outcome = try await router.route(makeCharacterIntent())
        let stored = try #require(await dependencies.repository.delivery)
        let expectedIntent = try makeCharacterIntent()

        #expect(outcome.route == testCase.expectedRoute)
        #expect(stored.decision.privacyMode == testCase.expectedPrivacy)
        #expect(stored.conversationItem.responseID == outcome.responseID)
        #expect(stored.conversationItem.text == expectedIntent.text)
        #expect(
            await dependencies.physicalSink.deliveryCount
                == (testCase.expectedRoute == .physicalSpeech ? 1 : 0))
        #expect(
            await dependencies.communicatorSink.deliveryCount
                == (testCase.expectedRoute == .communicator ? 1 : 0))
    }

    @Test("A presence transition cannot deliver one Beaky turn through both routes")
    func presenceTransitionKeepsFirstDurableDecision() async throws {
        let home = RoutingCase.home
        let dependencies = try makeRouterDependencies(testCase: home)
        let firstRouter = try makeRouter(dependencies: dependencies)
        let intent = try makeCharacterIntent()

        let first = try await firstRouter.route(intent)
        try await dependencies.presenceProvider.setPresence(makePresence(testCase: .away))
        let restartedRouter = try makeRouter(dependencies: dependencies)
        let afterRestart = try await restartedRouter.route(intent)

        #expect(first == afterRestart)
        #expect(first.route == .physicalSpeech)
        #expect(await dependencies.physicalSink.deliveryCount == 1)
        #expect(await dependencies.communicatorSink.deliveryCount == 0)
    }

    @Test("A response ID cannot be reused for a different Beaky turn")
    func conflictingResponseIdentityIsRejected() async throws {
        let dependencies = try makeRouterDependencies(testCase: .home)
        let router = try makeRouter(dependencies: dependencies)
        let original = try makeCharacterIntent()
        var conflict = original
        conflict.text = "Different Beaky words under the same response identity"

        _ = try await router.route(original)
        await #expect(throws: WorldContractError.conflictingConversationIdentity) {
            try await router.route(conflict)
        }

        #expect(await dependencies.physicalSink.deliveryCount == 1)
        #expect(await dependencies.communicatorSink.deliveryCount == 0)
    }

    @Test("A completed Beaky turn survives restart without needing presence again")
    func completedDeliveryDoesNotReevaluatePresence() async throws {
        let dependencies = try makeRouterDependencies(testCase: .home)
        let intent = try makeCharacterIntent()
        let firstRouter = try makeRouter(dependencies: dependencies)
        let first = try await firstRouter.route(intent)
        await dependencies.presenceProvider.becomeUnavailable()

        let restartedRouter = try makeRouter(dependencies: dependencies)
        let duplicate = try await restartedRouter.route(intent)

        #expect(duplicate == first)
        #expect(await dependencies.presenceProvider.readCount == 1)
        #expect(await dependencies.physicalSink.deliveryCount == 1)
    }

    @Test("A crash after sink acceptance retries the same stable attempt")
    func deliveryRetryUsesStableAttemptIdentity() async throws {
        let dependencies = try makeRouterDependencies(testCase: .away)
        await dependencies.communicatorSink.failOnceAfterAcceptance()
        let intent = try makeCharacterIntent()
        let firstRouter = try makeRouter(dependencies: dependencies)

        await #expect(throws: TestError.interruptedAfterAcceptance) {
            try await firstRouter.route(intent)
        }
        let attemptBeforeRestart = try #require(
            await dependencies.repository.delivery?.decision.attemptID
        )

        let restartedRouter = try makeRouter(dependencies: dependencies)
        let outcome = try await restartedRouter.route(intent)

        #expect(outcome.attemptID == attemptBeforeRestart)
        #expect(outcome.state == .duplicate)
        #expect(await dependencies.communicatorSink.acceptedAttemptCount == 1)
        #expect(await dependencies.physicalSink.deliveryCount == 0)
    }

    private func makeIngressService(
        repository: TestUtteranceRepository,
        sink: TestPerceptSink
    ) -> PersonUtteranceIngressService {
        PersonUtteranceIngressService(
            repository: repository,
            sink: sink,
            makeConsiderationID: {
                try! ConsiderationID(validating: "consideration:april-beaky-1")
            },
            makeConversationItemID: {
                try! ConversationItemID(validating: "conversation-item:april-1")
            }
        )
    }

    private func makeAdapterInput(sourceID: SourceID) throws -> PersonUtteranceAdapterInput {
        PersonUtteranceAdapterInput(
            utteranceID: try UtteranceID(validating: "utterance:april-1"),
            conversationID: try ConversationID(validating: "conversation:april-beaky"),
            speakerID: try EntityID(validating: "person:april"),
            addresseeIDs: [try EntityID(validating: "character:beaky")],
            text: "Beaky, how did that make you feel?",
            sourceID: sourceID,
            occurredAt: Self.now,
            confidence: 1,
            placeEvidence: try UtterancePlaceEvidence(
                placeID: EntityID(validating: "place:workshop"),
                confidence: 0.9,
                observedAt: Self.now.addingTimeInterval(-5),
                validUntil: Self.now.addingTimeInterval(60)
            ),
            trace: try W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-7a9c2f8e6b31d402-01"
            )
        )
    }

    private func makePriorItem() throws -> ConversationItem {
        try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:beaky-previous"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: "I was wondering what you thought.",
            createdAt: Self.now.addingTimeInterval(-30),
            responseID: ResponseID(validating: "response:beaky-previous")
        )
    }

    private func makeCharacterIntent() throws -> CharacterUtteranceIntent {
        try CharacterUtteranceIntent(
            responseID: ResponseID(validating: "response:beaky-1"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april"),
            inResponseToUtteranceID: UtteranceID(validating: "utterance:april-1"),
            text: "It made me curious what you would say next.",
            urgency: 0.3,
            createdAt: Self.now
        )
    }

    private func makePresence(testCase: RoutingCase) throws -> PersonPresence {
        try PersonPresence(
            personID: EntityID(validating: "person:april"),
            state: testCase.state,
            confidence: testCase.confidence,
            observedAt: Self.now.addingTimeInterval(-10),
            validUntil: Self.now.addingTimeInterval(testCase.validUntilOffset),
            physicallyAudible: testCase.physicallyAudible,
            placeID: testCase.state == .home ? EntityID(validating: "place:workshop") : nil
        )
    }

    private func makeRouterDependencies(
        testCase: RoutingCase
    ) throws -> RouterDependencies {
        RouterDependencies(
            presenceProvider: TestPresenceProvider(presence: try makePresence(testCase: testCase)),
            repository: TestDeliveryRepository(),
            physicalSink: TestDeliverySink(),
            communicatorSink: TestDeliverySink()
        )
    }

    private func makeRouter(
        dependencies: RouterDependencies
    ) throws -> CharacterDeliveryRouter {
        try CharacterDeliveryRouter(
            presenceProvider: dependencies.presenceProvider,
            repository: dependencies.repository,
            physicalSpeechSink: dependencies.physicalSink,
            communicatorSink: dependencies.communicatorSink,
            clock: ManualWorldClock(now: Self.now),
            makeAttemptID: {
                try! DeliveryAttemptID(validating: "delivery-attempt:beaky-1")
            },
            makeConversationItemID: {
                try! ConversationItemID(validating: "conversation-item:beaky-1")
            }
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_789_042_000)
}

private struct SemanticPercept: Hashable {
    let characterID: EntityID
    let speakerID: EntityID
    let addresseeIDs: [EntityID]
    let text: String
    let conversationID: ConversationID
    let priorConversationItems: [ConversationItem]

    init(_ percept: PersonUtterancePercept) {
        self.characterID = percept.characterID
        self.speakerID = percept.utterance.speakerID
        self.addresseeIDs = percept.utterance.addresseeIDs
        self.text = percept.utterance.text
        self.conversationID = percept.utterance.conversationID
        self.priorConversationItems = percept.priorConversationItems
    }
}

private actor TestUtteranceRepository: UtteranceIngressRepository {
    private var records: [UtteranceID: StoredUtteranceIngress] = [:]
    private var items: [ConversationItem]
    private var shouldFailNextCheckpoint = false

    init(priorItems: [ConversationItem] = []) {
        self.items = priorItems
    }

    var preparedCount: Int { records.count }

    func failNextCheckpoint() {
        shouldFailNextCheckpoint = true
    }

    func progress(for utteranceID: UtteranceID) -> UtteranceIngressProgress? {
        records[utteranceID]?.progress
    }

    func ingress(for utteranceID: UtteranceID) -> StoredUtteranceIngress? {
        records[utteranceID]
    }

    func conversationItems(in conversationID: ConversationID) -> [ConversationItem] {
        items.filter { $0.conversationID == conversationID }
    }

    func prepare(_ ingress: StoredUtteranceIngress) -> StoredUtteranceIngress {
        let utteranceID = ingress.percept.utterance.utteranceID
        if let existing = records[utteranceID] {
            return existing
        }
        records[utteranceID] = ingress
        items.append(ingress.conversationItem)
        return ingress
    }

    func markPerceptSubmitted(utteranceID: UtteranceID) throws {
        if shouldFailNextCheckpoint {
            shouldFailNextCheckpoint = false
            throw TestError.interruptedBeforeCheckpoint
        }
        records[utteranceID]?.progress = .perceptSubmitted
    }
}

private actor TestPerceptSink: PersonUtterancePerceptSink {
    private(set) var percepts: [PersonUtterancePercept] = []
    private var acceptedIDs: Set<UtteranceID> = []

    var submissionCount: Int { percepts.count }

    func submit(_ percept: PersonUtterancePercept) -> UtterancePerceptAcceptance {
        guard acceptedIDs.insert(percept.utterance.utteranceID).inserted else {
            return .duplicate
        }
        percepts.append(percept)
        return .accepted
    }
}

struct RoutingCase: Sendable, CustomTestStringConvertible {
    let state: PersonPresenceState
    let confidence: Double
    let validUntilOffset: TimeInterval
    let physicallyAudible: Bool
    let expectedRoute: CharacterDeliveryRoute
    let expectedPrivacy: CommunicatorPrivacyMode

    var testDescription: String {
        "\(state.rawValue)-\(expectedRoute.rawValue)-\(expectedPrivacy.rawValue)"
    }

    static let home = Self(
        state: .home,
        confidence: 0.98,
        validUntilOffset: 60,
        physicallyAudible: true,
        expectedRoute: .physicalSpeech,
        expectedPrivacy: .notApplicable
    )

    static let away = Self(
        state: .away,
        confidence: 0.98,
        validUntilOffset: 60,
        physicallyAudible: false,
        expectedRoute: .communicator,
        expectedPrivacy: .preview
    )
}

private struct RouterDependencies: Sendable {
    let presenceProvider: TestPresenceProvider
    let repository: TestDeliveryRepository
    let physicalSink: TestDeliverySink
    let communicatorSink: TestDeliverySink
}

private actor TestPresenceProvider: PersonPresenceProviding {
    private var currentPresence: PersonPresence
    private var isUnavailable = false
    private(set) var readCount = 0

    init(presence: PersonPresence) {
        self.currentPresence = presence
    }

    func presence(for personID: EntityID) throws -> PersonPresence {
        readCount += 1
        if isUnavailable {
            throw TestError.presenceUnavailable
        }
        return currentPresence
    }

    func setPresence(_ presence: PersonPresence) {
        currentPresence = presence
    }

    func becomeUnavailable() {
        isUnavailable = true
    }
}

private actor TestDeliveryRepository: CharacterDeliveryRepository {
    private(set) var delivery: StoredCharacterDelivery?

    func delivery(for responseID: ResponseID) -> StoredCharacterDelivery? {
        guard delivery?.intent.responseID == responseID else { return nil }
        return delivery
    }

    func prepare(_ proposed: StoredCharacterDelivery) -> StoredCharacterDelivery {
        if let delivery {
            return delivery
        }
        delivery = proposed
        return proposed
    }

    func record(_ outcome: CharacterDeliveryOutcome) {
        delivery?.outcome = outcome
    }
}

private enum TestError: Error {
    case interruptedBeforeCheckpoint
    case interruptedAfterAcceptance
    case presenceUnavailable
}

private actor TestDeliverySink: CharacterDeliverySink {
    private var acceptedAttempts: Set<DeliveryAttemptID> = []
    private var shouldFailAfterAcceptance = false
    private(set) var deliveryCount = 0

    var acceptedAttemptCount: Int { acceptedAttempts.count }

    func failOnceAfterAcceptance() {
        shouldFailAfterAcceptance = true
    }

    func deliver(
        _ intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) throws -> DeliverySinkResult {
        deliveryCount += 1
        let inserted = acceptedAttempts.insert(decision.attemptID).inserted
        if shouldFailAfterAcceptance {
            shouldFailAfterAcceptance = false
            throw TestError.interruptedAfterAcceptance
        }
        return DeliverySinkResult(state: inserted ? .accepted : .duplicate)
    }
}
