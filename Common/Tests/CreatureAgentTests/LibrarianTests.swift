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

    /// Something the librarian filed on an earlier night.
    private func filed(_ subject: EntityID, _ predicate: String, _ value: String, id: String)
        throws -> Fact
    {
        var fact = try kept(subject, predicate, value, id: id)
        fact.origin = try SourceID(validating: "librarian:beaky")
        return fact
    }

    private func answer(_ json: String) -> Data { Data(json.utf8) }

    /// The day record of the 14th, in small: April settling a question, and a bird's reply.
    private func day() throws -> DayDigest {
        DayDigest(
            day: "2026-10-14", timeZone: "America/Los_Angeles", happenings: [],
            conversation: [
                .init(
                    at: now.addingTimeInterval(60), who: "character:beaky", text: "Noted, April."),
                .init(
                    at: now, who: "person:april",
                    text: "The flight school is Wings Over Whidbey; the other one is it too."),
            ], scenes: [], learned: [])
    }

    /// A night's filing, as `GET /v1/filings` returns it.
    private func filing(day: String, questions: [String]) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: LibrarianFiling.filedEventType), occurredAt: now,
            source: EventSource(
                id: SourceID(validating: "mind:beaky"), kind: "mind",
                sourceEventID: "librarian:\(day):run"),
            subjectIDs: [beaky], epistemic: EpistemicState(type: .remembered, confidence: 1),
            payload: [
                "day": .string(day),
                "proposal": try LibrarianProposal(questions: questions).json,
            ])
    }

    @Test("What the librarian hears is what people said to the birds, in order, the newest kept")
    func hearsPeopleInOrder() throws {
        var lines: [DayDigest.Line] = [
            .init(at: now.addingTimeInterval(30), who: "character:kenny", text: "Kenny heard."),
            .init(at: now.addingTimeInterval(20), who: "person:april", text: "second"),
            .init(at: now.addingTimeInterval(10), who: "person:april", text: "first"),
        ]
        var heard = Librarian.Heard(
            DayDigest(
                day: "2026-10-20", timeZone: "America/Los_Angeles", happenings: [],
                conversation: lines, scenes: [], learned: []))
        #expect(heard.lines.map(\.text) == ["first", "second"])
        for index in 0..<(Librarian.maximumHeard + 5) {
            lines.append(
                .init(
                    at: now.addingTimeInterval(100 + Double(index)), who: "person:april",
                    text: "line \(index)"))
        }
        heard = Librarian.Heard(
            DayDigest(
                day: "2026-10-20", timeZone: "America/Los_Angeles", happenings: [],
                conversation: lines, scenes: [], learned: []))
        #expect(heard.lines.count == Librarian.maximumHeard)
        #expect(heard.lines.last?.text == "line \(Librarian.maximumHeard + 4)")
    }

    @Test("The record ends with what was asked last night and what April said, by the clock")
    func recordEndsWithAprilsWord() throws {
        let (learned, overwritten) = try record()
        let said = Date(timeIntervalSince1970: 1_792_545_119)  // 2026-10-20 6:11:59 PM, Pacific
        let heard = Librarian.Heard(
            DayDigest(
                day: "2026-10-20", timeZone: "America/Los_Angeles", happenings: [],
                conversation: [
                    .init(
                        at: said, who: "person:april",
                        text: "workshop.rebuild should be on the new workshop.")
                ], scenes: [], learned: []))
        let text = Librarian.record(
            learned: learned, overwritten: overwritten, kinds: [],
            asked: ["Which workshop notes describe the current room?"], heard: heard)
        #expect(
            text.hasSuffix(
                """
                What you asked April last night:
                  - Which workshop notes describe the current room?

                What April said to the birds on 2026-10-20, in order:
                  - 6:11 PM April: workshop.rebuild should be on the new workshop.
                """))
        let instructions = Librarian.instructions(name: "Beaky")
        #expect(instructions.contains("April's word settles the record"))
        #expect(instructions.contains("rewrite it onto the subject she named"))
        #expect(instructions.contains("never ask again what she has answered"))
        // The new workshop's hard floor, written over by the current one's carpet, stays put:
        // moved, it would end the carpet.
        #expect(instructions.contains("on the subject it was written over on"))
    }

    @Test(
        "The record holds what can be filed: never a kind with its own rules, a merged id, or bookkeeping; the librarian's own filings are in"
    )
    func recordIsHeldToWhatCanBeFiled() throws {
        let robin = try EntityID(validating: "person:robin")
        let robbin = try EntityID(validating: "person:robbin")
        let house = try EntityID(validating: "house:test-nest")
        let hardest = try kept(
            april, "flight.hardest_part", "landings", id: "00000000-0000-4000-8000-000000000011")
        let friend = try kept(
            robin, "person.relationship", "April's friend from the hangar",
            id: "00000000-0000-4000-8000-000000000012")
        let training = try filed(
            april, "flight.training", "flies on her own but for landings",
            id: "00000000-0000-4000-8000-000000000013")
        // Merged away by an applied filing; what no merge moves stayed behind on it.
        let merged = try filed(
            robbin, "entity.same_as", "person:robin", id: "00000000-0000-4000-8000-000000000014")
        let visit = try kept(
            robbin, "visitor.expected", "when the on-the-way text arrives", by: "caroll",
            id: "00000000-0000-4000-8000-000000000015")
        let stayed = try kept(
            robbin, "project.deck", "finishing the deck", by: "mango",
            id: "00000000-0000-4000-8000-000000000016")
        // A bird's own same-as, onto no id: bookkeeping, never filed, and merges nothing.
        let ownSameAs = try kept(
            robin, "entity.same_as", "person: Robin", id: "00000000-0000-4000-8000-000000000017")
        let quiet = try kept(
            house, "house.cameras_quiet", "the yard crew is working",
            id: "00000000-0000-4000-8000-000000000018")
        let (learned, mergedAway) = Librarian.shelf([
            hardest, friend, training, merged, visit, stayed, ownSameAs, quiet,
        ])
        #expect(learned == [hardest, friend, training])
        #expect(mergedAway == [robbin])

        let earlier = try kept(
            april, "flight.training", "learning to fly", id: "00000000-0000-4000-8000-000000000019")
        let oldVisit = try kept(
            robin, "visitor.expected", "Tuesday", id: "00000000-0000-4000-8000-00000000001a")
        let oldDeck = try kept(
            robbin, "project.deck", "starting the deck", id: "00000000-0000-4000-8000-00000000001b")
        let overwritten = Librarian.shelf(
            [
                OverwrittenFact(replaced: earlier, by: training),
                OverwrittenFact(replaced: oldVisit, by: visit),
                OverwrittenFact(replaced: oldDeck, by: stayed),
            ], merged: mergedAway)
        #expect(overwritten == [OverwrittenFact(replaced: earlier, by: training)])

        let text = Librarian.record(learned: learned, overwritten: overwritten, kinds: [])
        #expect(text.contains("What the minds kept, and what you filed before"))
        #expect(
            text.contains(
                "flight.training = flies on her own but for landings (filed by you"))
        #expect(text.contains("flight.hardest_part = landings (kept by mind:beaky"))
        #expect(text.contains("\"learning to fly\" (mind:beaky) was replaced by"))
        #expect(text.contains("\"flies on her own but for landings\" (you)"))
        for absent in ["visitor.expected", "entity.same_as", "house.cameras_quiet", "robbin"] {
            #expect(!text.contains(absent))
        }
    }

    @Test(
        "A proposal is held to what the review takes: no kind it guards, no name it would end, no meaning that exists"
    )
    func proposalsAreHeldToTheReview() throws {
        let robin = try EntityID(validating: "person:robin")
        let hardest = try kept(
            april, "flight.hardest_part", "landings", id: "00000000-0000-4000-8000-000000000021")
        let training = try filed(
            april, "flight.training", "flies on her own but for landings",
            id: "00000000-0000-4000-8000-000000000022")
        let friend = try kept(
            robin, "person.relationship", "April's friend from the hangar",
            id: "00000000-0000-4000-8000-000000000023")
        let proposal = Librarian.proposal(
            from: answer(
                """
                {"rewrites": [
                  {"subject": "person:april", "predicate": "visitor.expected", "value": "x",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000021"], "reason": "a kind with its own rules"},
                  {"subject": "person:robin", "predicate": "entity.same_as", "value": "person:april",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000023"], "reason": "bookkeeping"},
                  {"subject": "person:april", "predicate": "flight.training", "value": "landings",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000021"], "reason": "would end the filed one"},
                  {"subject": "person:april", "predicate": "flight.training",
                   "value": "flies on her own; landings are the hardest part",
                   "replaces": ["fact:00000000-0000-4000-8000-000000000022",
                                "fact:00000000-0000-4000-8000-000000000021"], "reason": "folds both"}
                ],
                "same": [{"ids": ["person:robin", "person:robbin"], "keep": "person:robin",
                          "sure": true, "reason": "merged already"}],
                "kinds": [{"predicate": "flight.training", "meaning": "already meant"},
                          {"predicate": "visitor.expected", "meaning": "has its own rules"},
                          {"predicate": "flight.hardest_part", "meaning": "what April finds hardest"}]}
                """), learned: [hardest, training, friend], overwritten: [],
            meant: ["flight.training"])
        #expect(proposal.rewrites.count == 1)
        #expect(proposal.rewrites.first?.replaces.count == 2)
        #expect(proposal.same.isEmpty)
        #expect(proposal.kinds.map(\.predicate) == ["flight.hardest_part"])
        // Three rewrites, a merge naming an id not in the record, two meanings.
        #expect(proposal.dropped == 6)
    }

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
        let filed = try filed(
            april, "flight.rules", "never alone in gusty wind",
            id: "00000000-0000-4000-8000-000000000031")
        let origins = Origins()
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/facts") { request, _ in
            let origin = request.uri.queryParameters["origin_prefix"].map(String.init)
            await origins.note(origin ?? "")
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            WorldFactPage(
                                facts: origin == "librarian:" ? [filed] : learned,
                                nextFactID: nil, hasMore: false)))))
        }
        router.get("world/v1/facts/overwritten") { request, _ in
            #expect(request.uri.queryParameters["since"] != nil)
            let origin = request.uri.queryParameters["origin_prefix"].map(String.init)
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            OverwrittenFactPage(items: origin == "mind:" ? overwritten : [])))))
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
        // What she said that day, and what was asked: this night's own filing from a run
        // before a retry is not last night's (#254).
        let day = try self.day()
        let filings = WorldFilingPage(events: [
            try filing(day: "2026-10-14", questions: ["Asked tonight already?"]),
            try filing(day: "2026-10-13", questions: ["Which flight school is the right one?"]),
        ])
        router.get("world/v1/days/2026-10-14") { request, _ in
            // The librarian is Beaky: what she heard, never another bird's whispers (#261).
            #expect(request.uri.queryParameters["mind"].map(String.init) == "character:beaky")
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(day))))
        }
        router.get("world/v1/filings") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(filings))))
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
        // What the minds kept and what the librarian filed before (#253).
        #expect(await origins.seen == ["mind:", "librarian:"])
        #expect(
            await asked.prompts.first?.contains("never alone in gusty wind (filed by you") == true)
        // What she said, and last night's questions - never this night's own (#254).
        let prompt = try #require(await asked.prompts.first)
        #expect(prompt.contains("What you asked April last night:\n  - Which flight school"))
        #expect(!prompt.contains("Asked tonight already?"))
        #expect(prompt.contains("What April said to the birds on 2026-10-14, in order:"))
        #expect(
            prompt.contains("The flight school is Wings Over Whidbey; the other one is it too."))
        #expect(!prompt.contains("Noted, April."))
        let events = await casts.events
        // Watching: the proposal and nothing else - no fact cast, no kind written.
        #expect(events.count == 1)
        let filing = try #require(events.first)
        #expect(filing.type.rawValue == "memory.filed")
        #expect(filing.payload["mode"] == .string("watching"))
        #expect(filing.payload["day"] == .string("2026-10-14"))
        #expect(filing.payload["learned"] == .number(6))
        #expect(filing.payload["overwritten"] == .number(1))
        #expect(filing.payload["heard"] == .number(1))
        #expect(filing.source.id.rawValue == "mind:beaky")
        #expect(
            filing.source.sourceEventID
                == "librarian:2026-10-14:5a8b0c8e-0000-4000-8000-000000000229")
        guard case .object(let proposal)? = filing.payload["proposal"],
            case .array(let retires)? = proposal["retires"],
            case .array(let questions)? = proposal["questions"]
        else {
            Issue.record("no proposal")
            return
        }
        #expect(retires.count == 1)
        #expect(questions == [.string("Is Amber Tamara?")])
        #expect(
            LibrarianProposal(filed: filing)?.renames.map(\.to.rawValue) == ["place:rocket-taco"])
    }

    @Test("A World that cannot say what April said or asked still has the night filed")
    func filesWithoutTheDay() async throws {
        let (learned, _) = try record()
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/facts") { request, _ in
            let origin = request.uri.queryParameters["origin_prefix"].map(String.init)
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            WorldFactPage(
                                facts: origin == "mind:" ? learned : [], nextFactID: nil,
                                hasMore: false)))))
        }
        router.get("world/v1/facts/overwritten") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(OverwrittenFactPage(items: [])))
                ))
        }
        router.get("world/v1/fact-kinds") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(FactKindPage(kinds: [])))))
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
                    ask: { transcript in
                        await asked.note(transcript.last?.content ?? "")
                        return Data("{}".utf8)
                    }),
                cast: { await casts.note($0) }, client: client,
                logger: Logger(label: "librarian-tests")
            ).file(
                day: "2026-10-14",
                run: try EventID(validating: "5a8b0c8e-0000-4000-8000-000000000231"), now: now)
        }
        #expect(await asked.prompts.first?.contains("What April said") == false)
        #expect(await asked.prompts.first?.contains("What you asked April") == false)
        #expect(await casts.events.first?.payload["heard"] == .number(0))
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
        // Two names for one thing are the librarian's, from April's words (#255).
        #expect(LearnedFact.contract.contains("two names are one"))
        #expect(LearnedFact.contract.contains("keep nothing for it"))
    }

    @Test("A bird's glossary holds only the kinds a mind may hold: never the World's own")
    func glossaryLeavesOutTheWorldsOwn() {
        func kind(_ predicate: String, _ audience: FactAudience = .minds) -> FactKind {
            FactKind(
                predicate: predicate, meaning: "what \(predicate) says", audience: audience,
                updatedAt: now, updatedBy: "world")
        }
        let meanings = Glossary.meanings(
            of: FactKindPage(kinds: [
                kind("flight.training"), kind(WorldFacts.entitySameAs),
                kind(WorldFacts.locationGPS), kind("contact.phone", .world),
                kind("visitor.expected"),
            ]))
        #expect(Set(meanings.keys) == ["flight.training", "visitor.expected"])
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

private actor Origins {
    private(set) var seen: [String] = []
    func note(_ origin: String) { seen.append(origin) }
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
