import Foundation
import Testing

@testable import Common

@Suite("DmxFixture JSON encoding and decoding")
struct DmxFixtureTests {

    // The canonical fixture payload from plan/dmx-fixture.md.
    private static let canonicalJson = """
        {
          "id": "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c",
          "name": "Stage Left Spot",
          "type": "light",
          "channel_offset": 500,
          "assigned_universe": 1,
          "channels": [
            { "offset": 0, "name": "red",        "kind": "color_red" },
            { "offset": 1, "name": "green",      "kind": "color_green" },
            { "offset": 2, "name": "blue",       "kind": "color_blue" },
            { "offset": 3, "name": "white",      "kind": "color_white" },
            { "offset": 4, "name": "blink",      "kind": "generic" },
            { "offset": 5, "name": "brightness", "kind": "master_dimmer" }
          ],
          "patterns": [
            {
              "id": "7d2a3b4c-5e6f-4789-a0b1-c2d3e4f5a6b7",
              "name": "Red Glow",
              "values": [
                { "channel": "red",        "value": 255 },
                { "channel": "brightness", "value": 200 }
              ],
              "fade_in_ms": 250,
              "fade_out_ms": 500,
              "hold_ms": 0
            }
          ],
          "bindings": [
            {
              "creature_id": "1a2b3c4d-5e6f-4789-a0b1-c2d3e4f5a6b7",
              "on_reason":   "ad_hoc",
              "on_state":    "running",
              "pattern_id":  "7d2a3b4c-5e6f-4789-a0b1-c2d3e4f5a6b7"
            }
          ]
        }
        """

    @Test("decodes the canonical fixture payload")
    func decodesCanonical() throws {
        let data = Data(Self.canonicalJson.utf8)
        let fixture = try JSONDecoder().decode(DmxFixture.self, from: data)

        #expect(fixture.id == "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c")
        #expect(fixture.name == "Stage Left Spot")
        #expect(fixture.type == .light)
        #expect(fixture.channelOffset == 500)
        #expect(fixture.assignedUniverse == 1)
        #expect(fixture.channels.count == 6)
        #expect(fixture.channels[0].name == "red")
        #expect(fixture.channels[0].kind == "color_red")
        #expect(fixture.channels[5].kind == "master_dimmer")
        #expect(fixture.patterns.count == 1)

        let pattern = fixture.patterns[0]
        #expect(pattern.id == "7d2a3b4c-5e6f-4789-a0b1-c2d3e4f5a6b7")
        #expect(pattern.name == "Red Glow")
        #expect(pattern.fadeInMs == 250)
        #expect(pattern.fadeOutMs == 500)
        #expect(pattern.holdMs == 0)
        #expect(pattern.values.count == 2)
        #expect(pattern.values[0].channel == "red")
        #expect(pattern.values[0].value == 255)

        #expect(fixture.bindings.count == 1)
        let binding = fixture.bindings[0]
        #expect(binding.creatureId == "1a2b3c4d-5e6f-4789-a0b1-c2d3e4f5a6b7")
        #expect(binding.onReason == .adHoc)
        #expect(binding.onState == .running)
        #expect(binding.patternId == "7d2a3b4c-5e6f-4789-a0b1-c2d3e4f5a6b7")
    }

    @Test("round-trips JSON")
    func roundTripsJson() throws {
        let data = Data(Self.canonicalJson.utf8)
        let decoded = try JSONDecoder().decode(DmxFixture.self, from: data)
        let reEncoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(DmxFixture.self, from: reEncoded)
        #expect(decoded == reDecoded)
    }

    @Test("encodes snake_case keys")
    func encodesSnakeCase() throws {
        let fixture = DmxFixture(
            id: "abc",
            name: "n",
            type: .light,
            channelOffset: 0,
            assignedUniverse: 7,
            channels: [FixtureChannel(offset: 0, name: "red", kind: "color_red")],
            patterns: [],
            bindings: []
        )
        let data = try JSONEncoder().encode(fixture)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["channel_offset"] as? Int == 0)
        #expect(json?["assigned_universe"] as? Int == 7)
        #expect(json?["channels"] != nil)
        // Should NOT have the camelCase variants leaking through.
        #expect(json?["channelOffset"] == nil)
        #expect(json?["assignedUniverse"] == nil)
    }

    @Test("unknown fixture type decodes to .generic (server is liberal)")
    func unknownTypeDecodesToGeneric() throws {
        let json = """
            {
              "id": "id1",
              "name": "Mystery Box",
              "type": "vendor-invented-thing",
              "channel_offset": 0,
              "channels": [{ "offset": 0, "name": "ch", "kind": "generic" }]
            }
            """
        let fixture = try JSONDecoder().decode(DmxFixture.self, from: Data(json.utf8))
        #expect(fixture.type == .generic)
    }

    @Test("decoding tolerates missing optional fields")
    func tolerantOfOmittedFields() throws {
        let json = """
            {
              "id": "id1",
              "name": "Minimal",
              "type": "generic",
              "channel_offset": 0,
              "channels": [{ "offset": 0, "name": "ch" }]
            }
            """
        let fixture = try JSONDecoder().decode(DmxFixture.self, from: Data(json.utf8))
        #expect(fixture.assignedUniverse == nil)
        #expect(fixture.patterns.isEmpty)
        #expect(fixture.bindings.isEmpty)
        #expect(fixture.channels[0].kind == "generic")
    }

    @Test("FixtureChannel kind defaults to generic when omitted")
    func channelKindDefaultsToGeneric() throws {
        let json = """
            { "offset": 0, "name": "smoke_output" }
            """
        let channel = try JSONDecoder().decode(FixtureChannel.self, from: Data(json.utf8))
        #expect(channel.kind == "generic")
    }

    @Test("FixtureBinding decodes with null on_reason/on_state as wildcard")
    func bindingWildcards() throws {
        let json = """
            {
              "creature_id": "abc",
              "on_reason": null,
              "on_state": null,
              "pattern_id": "pat"
            }
            """
        let binding = try JSONDecoder().decode(FixtureBinding.self, from: Data(json.utf8))
        #expect(binding.onReason == nil)
        #expect(binding.onState == nil)
    }

    @Test("FixtureBinding decodes with missing on_reason/on_state as wildcard")
    func bindingMissingFilters() throws {
        let json = """
            { "creature_id": "abc", "pattern_id": "pat" }
            """
        let binding = try JSONDecoder().decode(FixtureBinding.self, from: Data(json.utf8))
        #expect(binding.onReason == nil)
        #expect(binding.onState == nil)
    }

    @Test("FixturePattern fade timings default to zero")
    func patternTimingDefaults() throws {
        let json = """
            {
              "id": "p1",
              "name": "Snap",
              "values": [{ "channel": "x", "value": 0 }]
            }
            """
        let pattern = try JSONDecoder().decode(FixturePattern.self, from: Data(json.utf8))
        #expect(pattern.fadeInMs == 0)
        #expect(pattern.fadeOutMs == 0)
        #expect(pattern.holdMs == 0)
    }

    @Test("equal fixtures hash equally and compare equal")
    func equalityAndHashing() throws {
        let data = Data(Self.canonicalJson.utf8)
        let a = try JSONDecoder().decode(DmxFixture.self, from: data)
        let b = try JSONDecoder().decode(DmxFixture.self, from: data)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("differing channel order produces inequality")
    func differingChannelsProducesInequality() throws {
        let a = DmxFixture.mock()
        var b = a
        b.channels.reverse()
        #expect(a != b)
    }

    @Test("FixtureType encodes to the server's snake_case raw value")
    func typeEncodesSnakeCase() throws {
        let data = try JSONEncoder().encode(FixtureType.smokeMachine)
        #expect(String(data: data, encoding: .utf8) == "\"smoke_machine\"")
    }

    @Test("SetFixtureLiveDTO encodes timeout_ms as snake_case and round-trips")
    func liveDtoRoundTrip() throws {
        let dto = SetFixtureLiveDTO(
            values: [
                FixturePatternValue(channel: "red", value: 255),
                FixturePatternValue(channel: "brightness", value: 200),
            ],
            timeoutMs: 1000
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["timeout_ms"] as? Int) == 1000)
        #expect((json?["values"] as? [[String: Any]])?.count == 2)
        #expect(json?["timeoutMs"] == nil)

        let decoded = try JSONDecoder().decode(SetFixtureLiveDTO.self, from: data)
        #expect(decoded.timeoutMs == 1000)
        #expect(decoded.values.count == 2)
        #expect(decoded.values[0].channel == "red")
        #expect(decoded.values[0].value == 255)
    }
}
