import Foundation
import Testing
import WorldCore

@testable import creature_house

@Suite("House configuration")
struct HouseConfigurationTests {
    @Test("A house file names Home Assistant, the world, the house, and its mappings")
    func loadsConfiguration() throws {
        let configuration = try load(
            """
            { "home_assistant": { "url": "http://10.3.2.5:8123" },
              "house_id": "house:aprils-nest",
              "mappings": [
                { "entity_id": "lock.front_door", "subject_id": "place:front-door", "kind": "lock" },
                { "entity_id": "sensor.outside_temperature", "subject_id": "place:outside",
                  "kind": "measurement", "predicate": "temperature_f", "minimum_change": 0.5 },
                { "entity_id": "binary_sensor.front_door_person_detected", "subject_id": "place:front-door",
                  "kind": "detection", "detects": "person" }
              ] }
            """)
        #expect(configuration.homeAssistantURL.absoluteString == "http://10.3.2.5:8123")
        #expect(configuration.worldURL == HouseConfiguration.defaultWorldURL)
        #expect(configuration.houseID.rawValue == "house:aprils-nest")
        #expect(configuration.offersScenes)
        #expect(configuration.mappings.count == 3)
        #expect(configuration.mappings[1].minimumChange == 0.5)
        #expect(configuration.mappings[2].detects == .person)
    }

    @Test("Bad files are refused with a reason")
    func refusesBadFiles() {
        #expect(throws: HouseConfigurationError.self) {
            try load(#"{ "home_assistant": { "url": "10.3.2.5" }, "mappings": [] }"#)
        }
        #expect(throws: HouseConfigurationError.measurementNeedsPredicate("sensor.x")) {
            try load(
                #"{ "home_assistant": { "url": "http://h" }, "mappings": [{ "entity_id": "sensor.x", "subject_id": "place:x", "kind": "measurement" }] }"#
            )
        }
        #expect(throws: HouseConfigurationError.detectionNeedsDetects("binary_sensor.x")) {
            try load(
                #"{ "home_assistant": { "url": "http://h" }, "mappings": [{ "entity_id": "binary_sensor.x", "subject_id": "place:x", "kind": "detection" }] }"#
            )
        }
        #expect(throws: HouseConfigurationError.duplicateEntity) {
            try load(
                #"{ "home_assistant": { "url": "http://h" }, "mappings": [{ "entity_id": "lock.a", "subject_id": "place:a", "kind": "lock" }, { "entity_id": "lock.a", "subject_id": "place:b", "kind": "lock" }] }"#
            )
        }
    }

    private func load(_ json: String) throws -> HouseConfiguration {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "house-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try HouseConfiguration.load(from: url)
    }
}
