import Foundation
import Testing

@testable import Common

@Suite("DynamixelSensors tests")
struct DynamixelSensorsTests {

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let sensor = DynamixelSensors(
            dxlId: 7, temperatureF: 102.5, presentLoad: -42, voltageMv: 11800, voltageV: 11.8)
        #expect(sensor.dxlId == 7)
        #expect(sensor.temperatureF == 102.5)
        #expect(sensor.presentLoad == -42)
        #expect(sensor.voltageMv == 11800)
        #expect(sensor.voltageV == 11.8)
    }

    @Test("Identifiable id is the dxl id, not a synthesized UUID")
    func identifiableUsesDxlId() {
        let sensor = DynamixelSensors.mock()
        #expect(sensor.id == sensor.dxlId)
    }

    @Test("decodes from snake_case JSON")
    func decodesFromJSON() throws {
        let json = """
            {
                "dxl_id": 3,
                "temperature_f": 98.6,
                "present_load": 15,
                "voltage_mv": 12000,
                "voltage_v": 12.0
            }
            """
        let data = Data(json.utf8)
        let sensor = try JSONDecoder().decode(DynamixelSensors.self, from: data)
        #expect(sensor.dxlId == 3)
        #expect(sensor.temperatureF == 98.6)
        #expect(sensor.presentLoad == 15)
        #expect(sensor.voltageMv == 12000)
        #expect(sensor.voltageV == 12.0)
    }

    @Test("round-trips through encode and decode")
    func roundTrips() throws {
        let original = DynamixelSensors(
            dxlId: 11, temperatureF: 88.0, presentLoad: 0, voltageMv: 12100, voltageV: 12.1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DynamixelSensors.self, from: data)
        #expect(decoded == original)
    }

    @Test("equality and hashing ignore identity, compare values")
    func equalityAndHashing() {
        let a = DynamixelSensors(
            dxlId: 1, temperatureF: 90.0, presentLoad: 5, voltageMv: 12000, voltageV: 12.0)
        let b = DynamixelSensors(
            dxlId: 1, temperatureF: 90.0, presentLoad: 5, voltageMv: 12000, voltageV: 12.0)
        let c = DynamixelSensors(
            dxlId: 2, temperatureF: 90.0, presentLoad: 5, voltageMv: 12000, voltageV: 12.0)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
    }

    @Test("encodes with snake_case keys")
    func encodesSnakeCase() throws {
        let sensor = DynamixelSensors.mock()
        let data = try JSONEncoder().encode(sensor)
        let string = String(decoding: data, as: UTF8.self)
        #expect(string.contains("\"dxl_id\""))
        #expect(string.contains("\"temperature_f\""))
        #expect(string.contains("\"present_load\""))
        #expect(string.contains("\"voltage_mv\""))
        #expect(string.contains("\"voltage_v\""))
    }
}

@Suite("DynamixelSensorReport tests")
struct DynamixelSensorReportTests {

    @Test("decodes the dynamixel-sensor-report payload shape from the server")
    func decodesServerPayload() throws {
        // Mirrors DynamixelSensorReportCommandDTO on the server: creature_id is
        // snake_case while creatureName is camelCase, and the motors live under
        // "dynamixel_motors".
        let json = """
            {
                "creature_id": "creature_abc",
                "creatureName": "Beaky",
                "dynamixel_motors": [
                    { "dxl_id": 1, "temperature_f": 95.0, "present_load": -10, "voltage_mv": 12000, "voltage_v": 12.0 },
                    { "dxl_id": 2, "temperature_f": 101.2, "present_load": 33, "voltage_mv": 11900, "voltage_v": 11.9 }
                ]
            }
            """
        let data = Data(json.utf8)
        let report = try JSONDecoder().decode(DynamixelSensorReport.self, from: data)
        #expect(report.creatureId == "creature_abc")
        #expect(report.creatureName == "Beaky")
        #expect(report.motors.count == 2)
        #expect(report.motors[0].dxlId == 1)
        #expect(report.motors[1].presentLoad == 33)
    }

    @Test("decodes when the optional creatureName is missing")
    func decodesWithoutName() throws {
        let json = """
            {
                "creature_id": "creature_abc",
                "dynamixel_motors": []
            }
            """
        let data = Data(json.utf8)
        let report = try JSONDecoder().decode(DynamixelSensorReport.self, from: data)
        #expect(report.creatureId == "creature_abc")
        #expect(report.creatureName == nil)
        #expect(report.motors.isEmpty)
    }

    @Test("fails to decode when creature_id is missing")
    func failsWithoutCreatureId() {
        let json = """
            { "dynamixel_motors": [] }
            """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DynamixelSensorReport.self, from: data)
        }
    }

    @Test("decoding stamps the timestamp locally")
    func stampsTimestamp() throws {
        let before = Date()
        let json = """
            { "creature_id": "x", "dynamixel_motors": [] }
            """
        let report = try JSONDecoder().decode(
            DynamixelSensorReport.self, from: Data(json.utf8))
        let after = Date()
        #expect(report.timestamp >= before)
        #expect(report.timestamp <= after)
    }

    @Test("equality compares all fields")
    func equality() {
        let motors = [DynamixelSensors.mock()]
        let stamp = Date(timeIntervalSince1970: 1000)
        let a = DynamixelSensorReport(
            creatureId: "c1", creatureName: "Name", motors: motors, timestamp: stamp)
        let b = DynamixelSensorReport(
            creatureId: "c1", creatureName: "Name", motors: motors, timestamp: stamp)
        let c = DynamixelSensorReport(
            creatureId: "c2", creatureName: "Name", motors: motors, timestamp: stamp)
        #expect(a == b)
        #expect(a != c)
    }
}
