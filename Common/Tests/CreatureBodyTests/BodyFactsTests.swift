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
        #expect(Set(BodyFacts.meanings.keys).isSuperset(of: Set(facts.keys).union(motorFacts.keys)))
    }

    @Test("A Dynamixel report is every servo, the warmest, and the ones not answering")
    func servosBecomeFacts() {
        let report = DynamixelSensorReport(
            creatureId: "beaky-id", creatureName: "Beaky",
            motors: [
                DynamixelSensors(
                    dxlId: 1, temperatureF: 96.8, presentLoad: 120, voltageMv: 11_900,
                    voltageV: 11.9, presentPosition: 2048, online: true),
                DynamixelSensors(
                    dxlId: 2, temperatureF: 104.0, presentLoad: -40, voltageMv: 11_900,
                    voltageV: 11.9, presentPosition: 1700, online: true),
                DynamixelSensors(
                    dxlId: 3, temperatureF: 0, presentLoad: 0, voltageMv: 0, voltageV: 0,
                    presentPosition: nil, online: false),
            ])
        let facts = BodyFacts.facts(from: report)
        #expect(facts["body.servo_temperature_f"] == .string("104 °F, servo 2"))
        #expect(facts["body.servos_offline"] == .array([.string("3")]))
        guard case .object(let servos)? = facts["body.servos"] else {
            Issue.record("no servos")
            return
        }
        #expect(
            servos["2"]
                == .object([
                    "temperature_f": .number(104), "load": .number(-40), "volts": .number(11.9),
                    "online": .bool(true), "position": .number(1700),
                ]))
        // A servo going offline is a change worth saying, whatever the numbers.
        var back = servos
        back["3"] = .object([
            "temperature_f": .number(0), "load": .number(0), "volts": .number(0),
            "online": .bool(true),
        ])
        #expect(
            BodyFacts.changed(
                "body.servos", from: .object(servos), to: .object(back), thresholds: .init()))
        #expect(
            !BodyFacts.changed(
                "body.servos", from: .object(servos), to: .object(servos), thresholds: .init()))
        #expect(Set(BodyFacts.meanings.keys).isSuperset(of: facts.keys))
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

    @Test("The server's counters are its vital signs; a bird's runtime state is what it is doing")
    func serverAndRuntimeBecomeFacts() {
        var counters = SystemCountersDTO(totalFrames: 1_000, animationsPlayed: 7, soundsPlayed: 3)
        let first = BodyFacts.facts(from: counters, previous: nil, now: now)
        #expect(first["server.frames_per_second"] == nil)
        #expect(first["server.animations_played"] == .number(Double(counters.animationsPlayed)))
        counters.totalFrames += 6_000
        let second = BodyFacts.facts(
            from: counters,
            previous: (
                SystemCountersDTO(totalFrames: 1_000, animationsPlayed: 7, soundsPlayed: 3), now
            ), now: now + 60)
        #expect(second["server.frames_per_second"] == .number(100))
        #expect(Set(BodyFacts.meanings.keys).isSuperset(of: second.keys))

        // The error type has no public initializer: the runtime comes from JSON, as it does live.
        let runtime = try! JSONDecoder().decode(
            CreatureRuntime.self,
            from: Data(
                """
                {"idle_enabled": true,
                 "activity": {"state": "running", "animation_id": "a1", "reason": "ad_hoc"},
                 "last_error": {"message": "servo 3 timed out", "timestamp": 1789500000}}
                """.utf8))
        let facts = BodyFacts.facts(from: runtime)
        #expect(
            facts["body.activity"] == .string("playing an ad-hoc animation - speaking, most likely")
        )
        #expect(facts["body.idle_enabled"] == .bool(true))
        if case .string(let error)? = facts["body.last_error"] {
            #expect(error.hasPrefix("servo 3 timed out (at "))
        } else {
            Issue.record("no last error")
        }
        #expect(Set(BodyFacts.meanings.keys).isSuperset(of: facts.keys))
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
