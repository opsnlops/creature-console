import Foundation
import Logging
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// A whisper stays between April and one bird (#261), through the repositories the World runs
/// on: April's word and the bird's answer are marked where they are kept, every bird is handed
/// only what it heard, and the migration marks what was kept before.
@Suite(
    "Whispers in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct WhisperMongoTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let april = try! EntityID(validating: "person:april")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")

    private struct Harness {
        let persistence: MongoWorldPersistence
        let ingress: PersonUtteranceIngressService
        let router: CharacterDeliveryRouter
        let conversationID: ConversationID
        let april: EntityID
        let now: Date

        func say(_ text: String, minute: Double) async throws -> UtteranceIngressResult {
            try await ingress.ingest(
                try PersonUtterance(
                    conversationID: conversationID, speakerID: april,
                    addresseeIDs: [try EntityID(validating: "character:beaky")], text: text,
                    modality: .typed, source: .communicatorComposition,
                    sourceID: SourceID(validating: "communicator:test"),
                    occurredAt: now.addingTimeInterval(minute * 60), confidence: 1),
                context: UtteranceIngressContext(boundary: .trustedLAN))
        }

        func answer(_ said: UtteranceIngressResult, _ text: String) async throws
            -> CharacterDeliveryResult
        {
            try await router.route(
                try CharacterUtteranceIntent(
                    conversationID: conversationID, characterID: said.percept.characterID,
                    recipientID: april, inResponseToUtteranceID: said.percept.utterance.utteranceID,
                    text: text, urgency: 0.3,
                    createdAt: said.percept.utterance.occurredAt.addingTimeInterval(1)))
        }

        func items() async throws -> [ConversationItem] {
            try await persistence.conversations.conversationItems(
                in: conversationID, after: nil, limit: 50)
        }
    }

    private func harness() async throws -> Harness {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "whisper-tests"))
        let conversationID = try ConversationID(
            validating: "conversation:whisper-\(UUID().uuidString.lowercased())")
        return Harness(
            persistence: persistence,
            ingress: PersonUtteranceIngressService(
                repository: persistence.conversations, sink: AcceptingSink(),
                addresseeResolver: FlockResolver(
                    rule: LeadAddresseeRule(lead: beaky), present: ["beaky": beaky, "mango": mango])
            ),
            router: try CharacterDeliveryRouter(
                presenceProvider: AtHome(april: april, now: now),
                repository: persistence.characterDeliveries,
                physicalSpeechSink: AcceptingSink(), communicatorSink: AcceptingSink(),
                clock: ManualWorldClock(now: now)),
            conversationID: conversationID, april: april, now: now)
    }

    @Test("A whisper and its answer are kept marked, and only its bird is handed them")
    func whisperIsKeptMarked() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }

        let whisper = try await h.say("@beaky just between us", minute: 0)
        let answer = try await h.answer(whisper, "Just between us, April.")
        let toMango = try await h.say("Mango, how are the new speakers?", minute: 1)
        let toBeaky = try await h.say("Beaky, and you?", minute: 2)

        #expect(whisper.percept.characterID == beaky)
        #expect(answer.conversationItem.aloneWith == beaky)
        #expect(try await h.items().map(\.aloneWith) == [beaky, beaky, nil, nil])
        #expect(toMango.percept.characterID == mango)
        #expect(toMango.percept.priorConversationItems.isEmpty)
        #expect(
            toBeaky.percept.priorConversationItems.map(\.text) == [
                "@beaky just between us", "Just between us, April.",
                "Mango, how are the new speakers?",
            ])
        // A retry finds the same marked item: nothing conflicts.
        let retried = try await h.ingress.ingest(
            whisper.percept.utterance, context: UtteranceIngressContext(boundary: .trustedLAN))
        #expect(retried.disposition == .duplicate)
        #expect(try await h.answer(whisper, "Just between us, April.").disposition == .accepted)
    }

    @Test("The migration marks the whispers kept before it, and their answers, in every copy")
    func migrationMarksWhatWasKept() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let whisper = try await h.say("hey @beaky, just us?", minute: 0)
        let answer = try await h.answer(whisper, "Just us.")
        _ = try await h.say("Goodnight, flock", minute: 1)
        // As they were kept before 0.64.2: no mark anywhere.
        let database = h.persistence.database
        let unmark: Document = ["$unset": ["alone_with": ""] as Document]
        _ = try await database[MongoWorldCollection.conversationItems].updateMany(
            where: ["conversation_id": h.conversationID.rawValue], to: unmark)
        let unmarkCopy: Document = ["$unset": ["conversationItem.alone_with": ""] as Document]
        _ = try await database[MongoWorldCollection.utteranceIngresses].updateOne(
            where: ["_id": whisper.percept.utterance.utteranceID.rawValue], to: unmarkCopy)
        _ = try await database[MongoWorldCollection.characterDeliveries].updateOne(
            where: ["_id": answer.conversationItem.responseID!.rawValue], to: unmarkCopy)
        #expect(try await h.items().allSatisfy { $0.aloneWith == nil })

        let marked = try await MongoWorldMigrator(
            database: database, logger: Logger(label: "whisper-tests")
        ).markWhispers()

        #expect(marked >= 2)
        #expect(try await h.items().map(\.aloneWith) == [beaky, beaky, nil])
        // The copies match the items again: reading them back re-saves the item, which would
        // be refused if they differed.
        let ingress = try await h.persistence.conversations.ingress(
            for: whisper.percept.utterance.utteranceID)
        #expect(ingress?.conversationItem.aloneWith == beaky)
        let delivery = try await h.persistence.characterDeliveries.delivery(
            for: try #require(answer.conversationItem.responseID))
        #expect(delivery?.conversationItem.aloneWith == beaky)
        #expect(
            try await h.persistence.characterDeliveries.whisperedTo(
                utterance: whisper.percept.utterance.utteranceID) == beaky)
    }
}

private struct FlockResolver: AddresseeResolving {
    let rule: LeadAddresseeRule
    let present: [String: EntityID]

    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee {
        rule.addressee(in: utterance.text, present: present)
    }
}

private struct AcceptingSink: PersonUtterancePerceptSink, CharacterDeliverySink {
    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance {
        .accepted
    }

    func deliver(_ intent: CharacterUtteranceIntent, decision: CharacterDeliveryDecision)
        async throws -> DeliverySinkResult
    {
        DeliverySinkResult(state: .accepted)
    }
}

private struct AtHome: PersonPresenceProviding {
    let april: EntityID
    let now: Date

    func presence(for personID: EntityID) async throws -> PersonPresence {
        try PersonPresence(
            personID: april, state: .home, confidence: 0.98,
            observedAt: now.addingTimeInterval(-10), validUntil: now.addingTimeInterval(600),
            physicallyAudible: true, placeID: EntityID(validating: "place:workshop"))
    }
}
