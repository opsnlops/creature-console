import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_agent

/// #229: Beaky files what the minds kept, at night - watching first.
@Suite("The librarian")
struct LibrarianTests {
    private let beaky = try! EntityID(validating: "character:beaky")
    private let april = try! EntityID(validating: "person:april")
    private let school = try! EntityID(validating: "thing:wings-over-whidbey")
    private let schoolToo = try! EntityID(validating: "thing:april-s-flight-school")
    private let now = Date(timeIntervalSince1970: 1_789_390_200)

    private func kept(
        _ subject: EntityID, _ predicate: String, _ value: String, by bird: String = "beaky",
        id: String
    ) throws -> Fact {
        try Fact(
            factID: FactID(validating: "fact:\(id)"), subjectID: subject, predicate: predicate,
            value: .string(value), epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: now, derivedFrom: [],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
            origin: SourceID(validating: "mind:\(bird)"))
    }

    /// The night of 2026-10-14's flight talk, in small.
    private func record() throws -> (learned: [Fact], overwritten: [OverwrittenFact]) {
        let hardest = try kept(
            april, "flight.hardest_part", "landings", id: "00000000-0000-4000-8000-000000000001")
        let training = try kept(
            april, "person.flight_training", "pretty much flies on her own outside of landings",
            by: "mango", id: "00000000-0000-4000-8000-000000000002")
        let news = try kept(
            april, "person.news", "learning to fly a plane", by: "mango",
            id: "00000000-0000-4000-8000-000000000003")
        let name = try kept(
            school, "organization.name", "Wings Over Whidbey",
            id: "00000000-0000-4000-8000-000000000004")
        let named = try kept(
            schoolToo, "organization.name", "Wings Over Whidbey",
            id: "00000000-0000-4000-8000-000000000005")
        let gusty = try kept(
            april, "person.flight_training",
            "instructor wants her to fly in gusty wind conditions so she can learn",
            id: "00000000-0000-4000-8000-000000000009")
        return (
            [hardest, training, news, name, named],
            [OverwrittenFact(replaced: gusty, by: training)]
        )
    }

    private func answer(_ json: String) -> Data { Data(json.utf8) }

    @Test(
        "A rename is held to the ids shown as maybe the wrong kind, and to place, thing, or spell")
    func renamesAreHeldToTheCandidates() throws {
        let (learned, overwritten) = try record()
        let taco = try EntityID(validating: "person:rocket-taco")
        let proposal = Librarian.proposal(
            from: answer(
                #"""
                {"renames": [
                  {"id": "person:rocket-taco", "to": "place:rocket-taco", "reason": "a restaurant"},
                  {"id": "person:rocket-taco", "to": "thing:rocket-taco", "reason": "twice"},
                  {"id": "person:jesse", "to": "place:jesse", "reason": "not shown"},
                  {"id": "person:uucwi", "to": "character:uucwi", "reason": "never a bird"}
                ]}
                """#),
            learned: learned, overwritten: overwritten,
            candidates: [
                KindCandidate(id: taco, said: []),
                KindCandidate(id: try EntityID(validating: "person:uucwi"), said: []),
            ])
        #expect(proposal.renames.map(\.to.rawValue) == ["place:rocket-taco"])
        #expect(proposal.dropped == 3)
    }

    @Test("A proposal is held to the record: made-up ids, a fact twice, memories, and shapes drop")
    func proposalsAreHeldToTheRecord() throws {
        let (learned, overwritten) = try record()
        let proposal = Librarian.proposal(
            from: answer(
                """
                {"rewrites": [
                  {"subject": "person:april", "predicate": "flight.training",
                   "value": "flies on her own but for landings; her instructor has her practice in gusty wind",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000002"], "reason": "folds the written-over value back in"},
                  {"subject": "person:april", "predicate": "flight.again",
                   "value": "twice", "replaces": ["fact:00000000-0000-4000-8000-000000000002"], "reason": "the same fact again"},
                  {"subject": "person:nobody", "predicate": "flight.x", "value": "y",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000001"]},
                  {"subject": "person:april", "predicate": "memory.belief.beaky.9", "value": "y",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000001"]},
                  {"subject": "person:april", "predicate": "flight.made_up", "value": "y",
                   "replaces": ["fact:00000000-0000-4000-8000-0000000000ff"]}
                ],
                "retires": [{"fact": "fact:00000000-0000-4000-8000-000000000003", "reason": "old news"},
                            {"fact": "fact:00000000-0000-4000-8000-000000000002", "reason": "already rewritten"}],
                "same": [{"ids": ["thing:wings-over-whidbey", "thing:april-s-flight-school"],
                          "keep": "thing:wings-over-whidbey", "sure": true, "reason": "the same name"},
                         {"ids": ["person:amber"], "keep": "person:amber", "sure": true}],
                "kinds": [{"predicate": "flight.training", "meaning": "where April is in learning to fly"},
                          {"predicate": "not a predicate", "meaning": "x"}],
                "questions": ["Is Amber the cleaning lady from Quality Cleaning, Etc?"]}
                """), learned: learned, overwritten: overwritten)
        #expect(proposal.rewrites.count == 1)
        #expect(proposal.rewrites.first?.predicate == "flight.training")
        #expect(proposal.rewrites.first?.value.contains("gusty wind") == true)
        #expect(
            proposal.retires.map(\.fact.rawValue) == ["fact:00000000-0000-4000-8000-000000000003"])
        #expect(proposal.same.count == 1)
        #expect(proposal.same.first?.keep == school)
        #expect(proposal.same.first?.sure == true)
        #expect(proposal.kinds.map(\.predicate) == ["flight.training"])
        #expect(proposal.questions.count == 1)
        // Four bad rewrites, a retire of a fact already rewritten, a same of one, a bad kind.
        #expect(proposal.dropped == 7)
    }

    @Test("An answer that is not JSON proposes nothing, and says so")
    func nonsenseProposesNothing() throws {
        let (learned, overwritten) = try record()
        let proposal = Librarian.proposal(
            from: answer("I'd rather not."), learned: learned, overwritten: overwritten)
        #expect(proposal.rewrites.isEmpty && proposal.retires.isEmpty && proposal.same.isEmpty)
        #expect(proposal.dropped == 1)
    }

    @Test("No more than a night's changes: the rest wait for the next")
    func changesAreCapped() throws {
        var learned: [Fact] = []
        var retires: [String] = []
        for index in 0..<(Librarian.maximumChanges + 5) {
            let id = String(format: "00000000-0000-4000-8000-%012d", index + 100)
            learned.append(try kept(april, "misc.note_\(index)", "note", id: id))
            retires.append(#"{"fact": "fact:\#(id)", "reason": "old"}"#)
        }
        let proposal = Librarian.proposal(
            from: answer(#"{"retires": [\#(retires.joined(separator: ","))]}"#),
            learned: learned, overwritten: [])
        #expect(proposal.retires.count == Librarian.maximumChanges)
        #expect(proposal.dropped == 5)
    }

    @Test(
        "The record reads by subject, says who kept what, what was written over, and what kinds mean"
    )
    func recordReads() throws {
        let (learned, overwritten) = try record()
        let kind = FactKind(
            predicate: "flight.hardest_part", meaning: "what April finds hardest about flying",
            audience: .minds, updatedAt: now, updatedBy: "april")
        let unrelated = FactKind(
            predicate: "body.temperature_f", meaning: "a board's temperature", audience: .minds,
            updatedAt: now, updatedBy: "april")
        let kinds = Librarian.kinds(for: learned, from: FactKindPage(kinds: [unrelated, kind]))
        #expect(kinds.map(\.predicate) == ["flight.hardest_part"])
        let text = Librarian.record(learned: learned, overwritten: overwritten, kinds: kinds)
        #expect(text.contains("person:april"))
        #expect(
            text.contains(
                "[fact:00000000-0000-4000-8000-000000000001] flight.hardest_part = landings (kept by mind:beaky"
            ))
        #expect(text.contains("Written over since yesterday"))
        #expect(text.contains("gusty wind"))
        #expect(text.contains("flight.hardest_part: what April finds hardest about flying"))
        #expect(!text.contains("body.temperature_f"))
        let instructions = Librarian.instructions(name: "Beaky")
        #expect(instructions.contains("You are Beaky"))
        #expect(instructions.contains("never person.flight_landings"))
        #expect(instructions.contains("Never sure about a person from a role alone"))
        // Old deliveries a bird kept are Beaky's to recommend; the mail's orders settle (#234).
        #expect(instructions.contains("more than three days ago, retire it"))
        #expect(instructions.contains("the world settles by itself"))
    }

    @Test(
        "A night: the record read from the world, one question, the proposal recorded, nothing changed"
    )
    func filesTheNight() async throws {
        let (learned, overwritten) = try record()
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/facts") { request, _ in
            #expect(request.uri.queryParameters["origin_prefix"] == "mind:")
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            WorldFactPage(facts: learned, nextFactID: nil, hasMore: false)))))
        }
        router.get("world/v1/facts/overwritten") { request, _ in
            #expect(request.uri.queryParameters["since"] != nil)
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            OverwrittenFactPage(items: overwritten)))))
        }
        router.get("world/v1/fact-kinds") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(FactKindPage(kinds: [])))))
        }
        router.get("world/v1/librarian/kind-candidates") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            KindCandidatePage(candidates: [
                                KindCandidate(
                                    id: try EntityID(validating: "person:rocket-taco"),
                                    said: ["April often eats at Rocket Taco."])
                            ])))))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let casts = Casts()
        let asked = Asked()
        let beaky = self.beaky
        let now = self.now
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let librarian = Librarian(
                worldURL: URL(string: "http://localhost:\(port)/world/v1")!, characterID: beaky,
                persona: .text("You are Beaky."),
                model: MemoryModel(
                    modelName: "gpt-6-astra",
                    ask: { transcript in
                        await asked.note(transcript.last?.content ?? "")
                        return Data(
                            #"{"retires": [{"fact": "fact:00000000-0000-4000-8000-000000000003", "reason": "old news"}], "renames": [{"id": "person:rocket-taco", "to": "place:rocket-taco", "reason": "a taco restaurant"}], "questions": ["Is Amber Tamara?"]}"#
                                .utf8)
                    }),
                cast: { await casts.note($0) }, client: client,
                logger: Logger(label: "librarian-tests"))
            try await librarian.file(
                day: "2026-10-14",
                run: try EventID(validating: "5a8b0c8e-0000-4000-8000-000000000229"), now: now)
        }
        #expect(await asked.prompts.count == 1)
        #expect(await asked.prompts.first?.contains("Written over since yesterday") == true)
        #expect(await asked.prompts.first?.contains("May be the wrong kind") == true)
        #expect(await asked.prompts.first?.contains("April often eats at Rocket Taco.") == true)
        let events = await casts.events
        // Watching: the proposal and nothing else - no fact cast, no kind written.
        #expect(events.count == 1)
        let filed = try #require(events.first)
        #expect(filed.type.rawValue == "memory.filed")
        #expect(filed.payload["mode"] == .string("watching"))
        #expect(filed.payload["day"] == .string("2026-10-14"))
        #expect(filed.payload["learned"] == .number(5))
        #expect(filed.payload["overwritten"] == .number(1))
        #expect(filed.source.id.rawValue == "mind:beaky")
        #expect(
            filed.source.sourceEventID
                == "librarian:2026-10-14:5a8b0c8e-0000-4000-8000-000000000229")
        guard case .object(let proposal)? = filed.payload["proposal"],
            case .array(let retires)? = proposal["retires"],
            case .array(let questions)? = proposal["questions"]
        else {
            Issue.record("no proposal")
            return
        }
        #expect(retires.count == 1)
        #expect(questions == [.string("Is Amber Tamara?")])
        #expect(
            LibrarianProposal(filed: filed)?.renames.map(\.to.rawValue) == ["place:rocket-taco"])
    }

    @Test("A night with nothing kept asks nothing")
    func nothingKeptAsksNothing() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/facts") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            WorldFactPage(facts: [], nextFactID: nil, hasMore: false)))))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let casts = Casts()
        let asked = Asked()
        let beaky = self.beaky
        let now = self.now
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            try await Librarian(
                worldURL: URL(string: "http://localhost:\(port)/world/v1")!, characterID: beaky,
                persona: .text("You are Beaky."),
                model: MemoryModel(
                    modelName: "gpt-6-astra",
                    ask: { _ in
                        await asked.note("asked")
                        return Data("{}".utf8)
                    }),
                cast: { await casts.note($0) }, client: client,
                logger: Logger(label: "librarian-tests")
            ).file(
                day: "2026-10-14",
                run: try EventID(validating: "5a8b0c8e-0000-4000-8000-000000000230"), now: now)
        }
        #expect(await asked.prompts.isEmpty)
        #expect(await casts.events.isEmpty)
    }

    @Test("The learning contract keeps one value per name and names the family by topic")
    func contractSaysSo() {
        #expect(LearnedFact.contract.contains("never person.flight_landings"))
        #expect(LearnedFact.contract.contains("A name holds one value"))
        #expect(LearnedFact.contract.contains("old and new together"))
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Asked {
    private(set) var prompts: [String] = []
    func note(_ prompt: String) { prompts.append(prompt) }
}

/// #232: memories whole, and their meanings once.
@Suite("A fuller page, in the mind")
struct FullerPageMindTests {
    @Test("A memory's meaning rides once, by its family")
    func meaningsByFamily() {
        let folded = CharacterMind.byFamily([
            "memory.episode.beaky.2026-10-15.6": "something that happened",
            "memory.episode.beaky.2026-10-15.2": "something that happened",
            "memory.belief.beaky.1": "what you have come to believe",
            "door.lock": "whether the deadbolt is thrown",
        ])
        #expect(
            folded == [
                "memory.episode": "something that happened",
                "memory.belief": "what you have come to believe",
                "door.lock": "whether the deadbolt is thrown",
            ])
    }

    @Test("A long memory ends at its last whole sentence, never mid-word")
    func memoriesEndWhole() {
        let short = "April loves welcome-home greetings."
        #expect(MemoryJob.clipped(short) == short)
        let long =
            String(repeating: "April patiently tests the birds. ", count: 30)
            + "She is touched that I write to her"
        let clipped = MemoryJob.clipped(long)
        #expect(clipped.count <= MemoryJob.maximumMemoryCharacters)
        #expect(clipped.hasSuffix("."))
        #expect(!clipped.contains("She is touched"))
        // No sentence end in reach: the last whole word and an ellipsis.
        let words = String(repeating: "word ", count: 200)
        let cut = MemoryJob.clipped(words, to: 40)
        #expect(cut.hasSuffix("word…"))
        #expect(cut.count <= 41)
    }
}
