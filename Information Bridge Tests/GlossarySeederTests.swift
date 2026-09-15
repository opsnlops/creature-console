import Common
import CreatureAppSupport
import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The glossary, seeded")
struct GlossarySeederTests {
    @Test("New kinds are added, the Bridge's own are brought up to date, a Wizard's are left alone")
    func seedsAndUpdatesOnlyItsOwn() async throws {
        let now = Date()
        let world = GlossaryWorld(kinds: [
            FactKind(
                predicate: "order.expected", meaning: "in the carrier's words", updatedAt: now,
                updatedBy: "bridge:mail"),
            FactKind(
                predicate: "order.status", meaning: "April's own words here", updatedAt: now,
                updatedBy: "viewer:wizard"),
            FactKind(
                predicate: "order.total", meaning: "what it cost", updatedAt: now,
                updatedBy: "bridge:mail"),
        ])
        let client = WorldViewerClient(
            connection: CreatureServiceConnection(hostname: "w", port: 1, usesTLS: false),
            loader: world)
        try await GlossarySeeder(client: client, source: "mail").seed(
            [
                "order.expected": "as a day",
                "order.status": "the Bridge's newer words",
                "order.total": "what it cost",
                "order.last_heard": "the day the mail last spoke",
            ], worldOnly: ["order.last_heard"])
        let written = await world.written
        #expect(written.map(\.0) == ["order.expected", "order.last_heard"])
        #expect(written[0].1.meaning == "as a day")
        #expect(written[1].1.audience == .world)
        #expect(written.allSatisfy { $0.1.updatedBy == "bridge:mail" })
    }
}

/// A world with a glossary: answers the page, records the rewordings.
private actor GlossaryWorld: HTTPDataLoading {
    private let kinds: [FactKind]
    private(set) var written: [(String, FactKindUpdate)] = []

    init(kinds: [FactKind]) { self.kinds = kinds }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        if request.httpMethod == "PUT" {
            let update = try WorldJSON.makeDecoder().decode(
                FactKindUpdate.self, from: request.httpBody!)
            let predicate = request.url!.lastPathComponent
            written.append((predicate, update))
            let kind = FactKind(
                predicate: predicate, meaning: update.meaning, audience: update.audience ?? .minds,
                updatedAt: Date(), updatedBy: update.updatedBy)
            return (try WorldJSON.makeEncoder().encode(kind), response)
        }
        return (try WorldJSON.makeEncoder().encode(FactKindPage(kinds: kinds)), response)
    }
}
