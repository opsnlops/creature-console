import Foundation
import Testing
import WorldCore

@testable import World_Viewer

@Suite("The facts as a tree")
struct FactTreeTests {
    private func fact(_ subject: String, _ predicate: String, _ value: WorldJSONValue) throws
        -> Fact
    {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: value,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_000_000), derivedFrom: [],
            producer: FactProducer(kind: "test", id: "t", version: "1"))
    }

    @Test("Kind, entity, family, fact - with counts, sorted, and the leaf's fact reachable")
    func builds() throws {
        let facts = [
            try fact("person:april", "presence.state", .string("home")),
            try fact("person:april", "presence.physically_audible", .bool(true)),
            try fact("person:april", "person.relationship", .string("the one who feeds us")),
            try fact("place:driveway", "seen.vehicle", .bool(true)),
            try fact(
                "character:mango", "memory.belief.beaky.1", .object(["what": .string("jokes")])),
        ]
        let tree = FactTree.build(facts)
        #expect(tree.map(\.title) == ["character", "person", "place"])
        #expect(tree.map(\.count) == [1, 3, 1])
        let person = tree[1]
        #expect(person.children?.map(\.title) == ["april"])
        #expect(person.children?.first?.entity?.rawValue == "person:april")
        let families = person.children?.first?.children
        #expect(families?.map(\.title) == ["person.", "presence."])
        #expect(families?.map(\.count) == [1, 2])
        let leaves = families?[1].children
        #expect(
            leaves?.map(\.title) == ["presence.physically_audible", "presence.state"])
        let leaf = try #require(leaves?[1])
        #expect(FactTree.fact(inNodes: tree, id: leaf.id)?.predicate == "presence.state")
        #expect(FactTree.fact(inNodes: tree, id: "kind:person") == nil)
    }

    @Test(
        "Search words narrow to the facts that mention all of them, in subject, predicate, or value"
    )
    func narrows() throws {
        let facts = [
            try fact("person:april", "presence.state", .string("home")),
            try fact("person:jesse", "presence.state", .string("away")),
            try fact("house:aprils-nest", "visitor.expected", .string("Jesse, Sunday")),
        ]
        #expect(FactTree.matching(facts, query: "").count == 3)
        #expect(
            FactTree.matching(facts, query: "jesse").map(\.predicate) == [
                "presence.state", "visitor.expected",
            ])
        #expect(
            FactTree.matching(facts, query: "jesse sunday").map(\.predicate) == ["visitor.expected"]
        )
        #expect(
            FactTree.matching(facts, query: "presence home").map(\.subjectID.rawValue) == [
                "person:april"
            ])
        #expect(FactTree.matching(facts, query: "nobody").isEmpty)
    }
}
