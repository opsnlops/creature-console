import Foundation
import Testing

@testable import Common

@Suite("StreamFrameData tests")
struct StreamFrameDataTests {

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let frame = StreamFrameData(creatureId: "creature-1", universe: 2, data: "f39/fwAA")
        #expect(frame.creatureId == "creature-1")
        #expect(frame.universe == 2)
        #expect(frame.data == "f39/fwAA")
    }

    @Test("encodes with snake_case creature_id")
    func encodesSnakeCase() throws {
        let frame = StreamFrameData(creatureId: "creature-1", universe: 2, data: "f39/fwAA")
        let json = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
        #expect(json.contains("\"creature_id\""))
        #expect(json.contains("\"universe\""))
        #expect(json.contains("\"data\""))
    }

    @Test("round-trips through encode and decode")
    func roundTrips() throws {
        let original = StreamFrameData.mock()
        let decoded = try JSONDecoder().decode(
            StreamFrameData.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("equality compares all fields")
    func equality() {
        let a = StreamFrameData(creatureId: "c1", universe: 1, data: "AAAA")
        let b = StreamFrameData(creatureId: "c1", universe: 1, data: "AAAA")
        let c = StreamFrameData(creatureId: "c1", universe: 2, data: "AAAA")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
    }
}
