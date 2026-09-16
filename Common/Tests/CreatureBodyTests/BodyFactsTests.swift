import Common
import Foundation
import Testing
import WorldCore

@testable import creature_body

@Suite("The birds' bodies, as facts")
struct BodyFactsTests {
    private let beaky = try! EntityID(validating: "character:beaky")
    private let now = Date(timeIntervalSince1970: 1_789_500_000)

    private func board(_ temperature: Double, volts: Double = 12.0, amps: Double = 1.2)
        -> BoardSensorReport
    {
        BoardSensorReport(
            creatureId: "beaky-id", boardTemperature: temperature,
            powerReports: [
                BoardPowerSensors(
                    name: "servos", current: amps, power: volts * amps, voltage: volts)
            ])
    }

    @Test(
        "A board report is the temperature and the rails; a motor report the motors and their load")
    func reportsBecomeFacts() {
        let facts = BodyFacts.facts(from: board(77.44, volts: 12.04, amps: 1.234))
        #expect(facts["body.board_temperature_f"] == .number(77.4))
        #expect(
            facts["body.power"]
                == .object([
                    "servos": .object([
                        "volts": .number(12.04), "amps": .number(1.23), "watts": .number(14.86),
                    ])
                ]))
        let motors = MotorSensorReport(
            creatureId: "beaky-id",
            motors: [
                MotorSensors(motorNumber: 1, position: 1500, current: 0.4, power: 4.8, voltage: 12),
                MotorSensors(motorNumber: 2, position: 900, current: 0.25, power: 3.0, voltage: 12),
            ])
        let motorFacts = BodyFacts.facts(from: motors)
        #expect(motorFacts["body.motor_load_a"] == .number(0.65))
        guard case .object(let byMotor)? = motorFacts["body.motors"] else {
            Issue.record("no motors")
            return
        }
        #expect(byMotor.count == 2)
        #expect(
            byMotor["1"]
                == .object(["position": .number(1500), "amps": .number(0.4), "watts": .number(4.8)])
        )
        #expect(Set(BodyFacts.meanings.keys) == Set(facts.keys).union(motorFacts.keys))
    }

    @Test(
        "Small changes are not said; big ones are, once the interval is up; steady values are said again before they are forgotten"
    )
    func changesAreJudged() {
        var ledger = BodyLedger()
        let thresholds = BodyConfiguration.Thresholds()
        func changes(_ temperature: Double, at seconds: TimeInterval) -> [String] {
            ledger.changes(
                for: beaky, facts: BodyFacts.facts(from: board(temperature)),
                now: now.addingTimeInterval(seconds), thresholds: thresholds,
                minimumInterval: 30, validFor: 600
            ).map(\.predicate)
        }
        #expect(changes(77.0, at: 0) == ["body.board_temperature_f", "body.power"])  // first word
        #expect(changes(77.2, at: 1).isEmpty)  // within the interval
        #expect(changes(77.2, at: 31).isEmpty)  // too small a change
        #expect(changes(78.0, at: 32) == ["body.board_temperature_f"])  // a degree is news
        #expect(changes(78.0, at: 300).isEmpty)  // steady
        #expect(changes(78.0, at: 520) == ["body.board_temperature_f", "body.power"])  // said again at 80% of its life
    }

    @Test("A creature's name finds its entity; the configuration can say otherwise")
    func namesBecomeEntities() throws {
        var configuration = BodyConfiguration()
        #expect(configuration.character(named: "Beaky")?.rawValue == "character:beaky")
        #expect(configuration.character(named: "Left Ear!")?.rawValue == "character:left-ear")
        configuration.characters["left ear!"] = try EntityID(validating: "character:lefty")
        #expect(configuration.character(named: "Left Ear!")?.rawValue == "character:lefty")
    }

    @Test("The file, the environment, and nothing at all all make a configuration")
    func configurationLoads() throws {
        let file = FileManager.default.temporaryDirectory.appending(
            path: "body-\(UUID().uuidString).json")
        try Data(
            """
            {"server_host": "server.local", "server_port": 8000, "world_url": "http://world.local/world/v1",
             "minimum_interval_seconds": 45, "thresholds": {"temperature_f": 1.0}, "characters": {"Beaky": "character:beaky"}}
            """.utf8
        ).write(to: file)
        let fromFile = try BodyConfiguration.load(from: file, environment: [:])
        #expect(fromFile.serverHost == "server.local")
        #expect(fromFile.minimumIntervalSeconds == 45)
        #expect(fromFile.thresholds.temperatureF == 1.0)
        #expect(fromFile.thresholds.volts == 0.1)
        let overridden = try BodyConfiguration.load(
            from: file,
            environment: ["CREATURE_SERVER_HOST": "elsewhere", "CREATURE_PROXY_API_KEY": "k"])
        #expect(overridden.serverHost == "elsewhere")
        #expect(overridden.proxyAPIKey == "k")
        let bare = try BodyConfiguration.load(from: nil, environment: [:])
        #expect(bare.worldURL.absoluteString == "http://127.0.0.1:8001/world/v1")
        #expect(throws: BodyConfigurationError.self) {
            try BodyConfiguration.load(from: nil, environment: ["CREATURE_SERVER_PORT": "eighty"])
        }
    }
}
