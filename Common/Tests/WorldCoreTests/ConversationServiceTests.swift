import Foundation
import Testing

@testable import WorldCore

@Suite("Unified bidirectional conversation pipeline")
struct ConversationServiceTests {
    @Test("Communicator, Wizard Mode, and future speech share Beaky's percept path")
    func adaptersShareOnePerceptPath() async throws {
        let adapters: [PersonUtteranceAdapter] = [
            .communicatorComposition,
            .wizardMode,
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
                .communicatorComposition, .wizardMode, .speechToText,
            ])
        #expect(percepts.map(\.utterance.modality) == [.typed, .typed, .spoken])
    }

    @Test("April's ordered turns build the conversation context Beaky hears")
    func orderedTurnsBuildConversationContext() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = PersonUtteranceIngressService(repository: repository, sink: sink)
        let first = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        var second = first
        second.utteranceID = try UtteranceID(validating: "utterance:april-2")
        second.text = "I am answering because what you say matters to me."
        second.occurredAt = first.occurredAt.addingTimeInterval(1)

        _ = try await PersonUtteranceAdapter.wizardMode.submit(
            first,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: service
        )
        _ = try await PersonUtteranceAdapter.wizardMode.submit(
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
        let input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        let firstService = makeIngressService(repository: repository, sink: sink)

        let first = try await PersonUtteranceAdapter.wizardMode.submit(
            input,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: firstService
        )
        let restartedService = makeIngressService(repository: repository, sink: sink)
        let duplicate = try await PersonUtteranceAdapter.wizardMode.submit(
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

    @Test("Concurrent ingress accepts one April turn and one duplicate")
    func concurrentIngressIsIdempotent() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let firstService = makeIngressService(repository: repository, sink: sink)
        let secondService = makeIngressService(repository: repository, sink: sink)
        let input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        let context = UtteranceIngressContext(boundary: .trustedLAN)

        async let first = PersonUtteranceAdapter.wizardMode.submit(
            input,
            context: context,
            to: firstService
        )
        async let second = PersonUtteranceAdapter.wizardMode.submit(
            input,
            context: context,
            to: secondService
        )
        let results = try await [first, second]

        #expect(Set(results.map(\.disposition)) == [.accepted, .duplicate])
        #expect(Set(results.map(\.percept.considerationID)).count == 1)
        #expect(Set(results.map(\.conversationItem.itemID)).count == 1)
        #expect(await repository.preparedCount == 1)
        #expect(await sink.submissionCount == 1)
    }

    @Test("A retry that arrives under a new transport trace is still the same utterance")
    func retryWithDifferentTraceIsDuplicate() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = makeIngressService(repository: repository, sink: sink)
        var first = try makeAdapterInput(sourceID: SourceID(validating: "communicator:app"))
        first.trace = try W3CTraceContext(
            traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
        var retry = first
        retry.trace = try W3CTraceContext(
            traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-11f067aa0ba902b7-01")
        let context = UtteranceIngressContext(boundary: .trustedLAN)

        let accepted = try await PersonUtteranceAdapter.communicatorComposition.submit(
            first, context: context, to: service)
        let duplicate = try await PersonUtteranceAdapter.communicatorComposition.submit(
            retry, context: context, to: service)

        #expect(accepted.disposition == .accepted)
        #expect(duplicate.disposition == .duplicate)
        #expect(duplicate.percept.utterance.trace == first.trace)
        #expect(await sink.submissionCount == 1)
    }

    @Test("A long conversation still carries a bounded window into the percept (#156)")
    func longConversationIsWindowed() async throws {
        let repository = TestUtteranceRepository()
        let service = PersonUtteranceIngressService(
            repository: repository, sink: TestPerceptSink())
        let context = UtteranceIngressContext(boundary: .trustedLAN)
        for index in 0..<(ConversationContractLimits.maximumContextItems + 5) {
            var input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
            input.utteranceID = try UtteranceID(validating: "utterance:long-\(index)")
            input.text = "Message \(index)"
            input.occurredAt = input.occurredAt.addingTimeInterval(Double(index))
            _ = try await PersonUtteranceAdapter.wizardMode.submit(
                input, context: context, to: service)
        }
        var lastInput = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        lastInput.utteranceID = try UtteranceID(validating: "utterance:long-last")
        lastInput.text = "Still listening?"
        lastInput.occurredAt = lastInput.occurredAt.addingTimeInterval(1_000)

        let last = try await PersonUtteranceAdapter.wizardMode.submit(
            lastInput, context: context, to: service)

        #expect(last.disposition == .accepted)
        #expect(
            last.percept.priorConversationItems.count
                == ConversationContractLimits.maximumContextItems)
        #expect(last.percept.priorConversationItems.last?.text == "Message 104")
        #expect(last.percept.priorConversationItems.first?.text == "Message 5")
    }

    @Test("An utterance ID cannot be reused to make Beaky hear different words")
    func conflictingUtteranceIdentityIsRejected() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = makeIngressService(repository: repository, sink: sink)
        let original = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        var conflict = original
        conflict.text = "Different words under the same identity"

        _ = try await PersonUtteranceAdapter.wizardMode.submit(
            original,
            context: UtteranceIngressContext(boundary: .trustedLAN),
            to: service
        )
        await #expect(throws: WorldContractError.conflictingConversationIdentity) {
            try await PersonUtteranceAdapter.wizardMode.submit(
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
        let input = try makeAdapterInput(sourceID: SourceID(validating: "wizard:mode"))
        let firstService = makeIngressService(repository: repository, sink: sink)

        await #expect(throws: TestError.interruptedBeforeCheckpoint) {
            try await PersonUtteranceAdapter.wizardMode.submit(
                input,
                context: UtteranceIngressContext(boundary: .trustedLAN),
                to: firstService
            )
        }

        let restartedService = makeIngressService(repository: repository, sink: sink)
        let retry = try await PersonUtteranceAdapter.wizardMode.submit(
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

    @Test("Authenticated Communicator calls cannot impersonate Wizard Mode or speech")
    func authenticatedGatewayRejectsPrivilegedSources() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = makeIngressService(repository: repository, sink: sink)
        let input = try makeAdapterInput(
            sourceID: SourceID(validating: "communicator:april-iphone")
        )
        let context = UtteranceIngressContext(
            boundary: .authenticatedGateway,
            principalID: input.speakerID
        )

        await #expect(throws: WorldContractError.unauthorizedUtteranceIngress) {
            try await PersonUtteranceAdapter.wizardMode.submit(input, context: context, to: service)
        }
        await #expect(throws: WorldContractError.unauthorizedUtteranceIngress) {
            try await PersonUtteranceAdapter.speechToText.submit(
                input,
                context: context,
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

        let result = try await router.route(makeCharacterIntent())
        let outcome = result.outcome
        let stored = try #require(await dependencies.repository.delivery)
        let expectedIntent = try makeCharacterIntent()

        #expect(result.disposition == .accepted)
        #expect(result.conversationItem == stored.conversationItem)
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

        #expect(first.outcome == afterRestart.outcome)
        #expect(first.conversationItem == afterRestart.conversationItem)
        #expect(first.disposition == .accepted)
        #expect(afterRestart.disposition == .duplicate)
        #expect(first.outcome.route == .physicalSpeech)
        #expect(await dependencies.physicalSink.deliveryCount == 1)
        #expect(await dependencies.communicatorSink.deliveryCount == 0)
    }

    @Test("A concurrent presence transition still chooses only one stage for Beaky")
    func concurrentPresenceTransitionChoosesOneRoute() async throws {
        let repository = TestDeliveryRepository()
        let physicalSink = TestDeliverySink()
        let communicatorSink = TestDeliverySink()
        let homeRouter = try makeRouter(
            dependencies: RouterDependencies(
                presenceProvider: TestPresenceProvider(presence: try makePresence(testCase: .home)),
                repository: repository,
                physicalSink: physicalSink,
                communicatorSink: communicatorSink
            )
        )
        let awayRouter = try makeRouter(
            dependencies: RouterDependencies(
                presenceProvider: TestPresenceProvider(presence: try makePresence(testCase: .away)),
                repository: repository,
                physicalSink: physicalSink,
                communicatorSink: communicatorSink
            )
        )
        let intent = try makeCharacterIntent()

        async let homeResult = homeRouter.route(intent)
        async let awayResult = awayRouter.route(intent)
        let outcomes = try await [homeResult, awayResult].map(\.outcome)
        let physicalAcceptances = await physicalSink.acceptedAttemptCount
        let communicatorAcceptances = await communicatorSink.acceptedAttemptCount
        let physicalDeliveries = await physicalSink.deliveryCount
        let communicatorDeliveries = await communicatorSink.deliveryCount

        #expect(Set(outcomes.map(\.route)).count == 1)
        #expect(physicalAcceptances + communicatorAcceptances == 1)
        #expect((physicalDeliveries == 0) != (communicatorDeliveries == 0))
        #expect(await repository.preparedCount == 1)
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

        #expect(duplicate.outcome == first.outcome)
        #expect(duplicate.disposition == .duplicate)
        #expect(await dependencies.presenceProvider.readCount == 1)
        #expect(await dependencies.physicalSink.deliveryCount == 1)
    }

    @Test("The stage is decided once, before the words exist, and the same answer is repeated")
    func stageDecisionIsDurableAndIdempotent() async throws {
        let dependencies = try makeRouterDependencies(testCase: .home)
        let router = try makeRouter(dependencies: dependencies)
        let request = try makeStageRequest()

        let first = try await router.stage(request, in: Self.conversationID)
        try await dependencies.presenceProvider.setPresence(makePresence(testCase: .away))
        let again = try await makeRouter(dependencies: dependencies).stage(
            request, in: Self.conversationID)

        #expect(first.disposition == .decided)
        #expect(first.decision.route == .physicalSpeech)
        #expect(first.decision.reason == .homeAndAudible)
        #expect(again == first)
        #expect(await dependencies.presenceProvider.readCount == 1)
        #expect(await dependencies.repository.stage?.expiresAt == Self.now.addingTimeInterval(300))
    }

    @Test("A performed turn is recorded on the stage the world decided, once")
    func performanceIsRecordedOnStagedDecision() async throws {
        let dependencies = try makeRouterDependencies(testCase: .home)
        let router = try makeRouter(dependencies: dependencies)
        let request = try makeStageRequest()
        let staged = try await router.stage(request, in: Self.conversationID)
        let performance = try CharacterPerformance(
            intent: makeCharacterIntent(),
            attemptID: staged.decision.attemptID,
            outcome: CharacterPerformanceReport(state: .performed, providerReference: "anim-42")
        )

        let result = try await router.recordPerformance(
            performance, in: Self.conversationID)
        let replay = try await makeRouter(dependencies: dependencies).recordPerformance(
            performance, in: Self.conversationID)

        #expect(result.disposition == .accepted)
        #expect(result.outcome.state == .performed)
        #expect(result.outcome.providerReference == "anim-42")
        #expect(result.outcome.route == .physicalSpeech)
        #expect(result.conversationItem.text == performance.intent.text)
        #expect(replay.disposition == .duplicate)
        #expect(replay.outcome == result.outcome)
        // The world never speaks for a mind that performed itself.
        #expect(await dependencies.physicalSink.deliveryCount == 0)
        #expect(await dependencies.communicatorSink.deliveryCount == 0)
    }

    @Test("A performance the world never staged is refused")
    func unstagedPerformanceIsRefused() async throws {
        let dependencies = try makeRouterDependencies(testCase: .home)
        let router = try makeRouter(dependencies: dependencies)
        let performance = try CharacterPerformance(
            intent: makeCharacterIntent(),
            attemptID: DeliveryAttemptID(validating: "delivery-attempt:nobody-asked"),
            outcome: CharacterPerformanceReport(state: .performed)
        )

        await #expect(throws: WorldContractError.unstagedPerformance) {
            try await router.recordPerformance(
                performance, in: performance.intent.conversationID)
        }
        #expect(await dependencies.repository.delivery == nil)
    }

    @Test("Asking for the stage of a turn already carried says so, so it is never performed twice")
    func stageReportsAlreadyDelivered() async throws {
        let dependencies = try makeRouterDependencies(testCase: .away)
        let router = try makeRouter(dependencies: dependencies)
        let intent = try makeCharacterIntent()
        let delivered = try await router.route(intent)

        let stage = try await router.stage(
            makeStageRequest(), in: intent.conversationID)

        #expect(stage.disposition == .alreadyDelivered)
        #expect(stage.decision.attemptID == delivered.outcome.attemptID)
        #expect(stage.delivery?.outcome == delivered.outcome)
        #expect(stage.delivery?.conversationItem == delivered.conversationItem)
    }

    @Test("A routed turn honours the stage the mind was told, even if presence moved")
    func routeHonoursPriorStageDecision() async throws {
        let dependencies = try makeRouterDependencies(testCase: .away)
        let router = try makeRouter(dependencies: dependencies)
        let request = try makeStageRequest()
        let staged = try await router.stage(request, in: Self.conversationID)
        try await dependencies.presenceProvider.setPresence(makePresence(testCase: .home))

        let result = try await router.route(makeCharacterIntent())

        #expect(staged.decision.route == .communicator)
        #expect(result.outcome.route == .communicator)
        #expect(result.outcome.attemptID == staged.decision.attemptID)
        #expect(await dependencies.presenceProvider.readCount == 1)
        #expect(await dependencies.communicatorSink.deliveryCount == 1)
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
        let result = try await restartedRouter.route(intent)
        let outcome = result.outcome

        // The retry completes the first attempt; the sink is what recognised the replay.
        #expect(result.disposition == .accepted)
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

    private func makeStageRequest() throws -> CharacterStageRequest {
        try CharacterStageRequest(
            responseID: ResponseID(validating: "response:beaky-1"),
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april")
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
    private static let conversationID = try! ConversationID(validating: "conversation:april-beaky")
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

    func newestConversationItems(in conversationID: ConversationID, limit: Int)
        -> [ConversationItem]
    {
        Array(items.filter { $0.conversationID == conversationID }.suffix(limit))
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
    private(set) var stage: StoredStageDecision?

    var preparedCount: Int { delivery == nil ? 0 : 1 }

    func stageDecision(for responseID: ResponseID) -> StoredStageDecision? {
        guard stage?.decision.responseID == responseID else { return nil }
        return stage
    }

    func prepareStage(_ proposed: StoredStageDecision) -> StoredStageDecision {
        if let stage {
            return stage
        }
        stage = proposed
        return proposed
    }

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
