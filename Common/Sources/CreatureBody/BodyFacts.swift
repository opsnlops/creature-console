import Common
import Foundation
import WorldCore

/// The birds are curious what their sensors say. Each report from Creature Server becomes a
/// few facts on the bird itself - its board temperature, its power rails, its motors - said
/// only when they change by more than a threshold and no more often than the interval, each
/// valid a few minutes so a bird that goes quiet stops feeling its body.
enum BodyFacts {
    static let eventType = WorldEventType(rawValue: "facts.given")!
    static let sourceID = try! SourceID(validating: "body:sensors")
    static let sourceKind = "body"

    static let meanings: [String: String] = [
        "body.board_temperature_f":
            "the temperature of the bird's own control board, in degrees Fahrenheit, as its sensors read it",
        "body.power":
            "the bird's power rails as its sensors read them: for each rail, volts, amps, and watts",
        "body.motors":
            "the bird's motors as its sensors read them: for each motor, its position and the amps and watts it is drawing",
        "body.motor_load_a":
            "how hard the bird's motors are working right now: the amps drawn by all of them together",
    ]

    /// The facts a board report makes.
    static func facts(from report: BoardSensorReport) -> [String: WorldJSONValue] {
        var rails: [String: WorldJSONValue] = [:]
        for rail in report.powerReports {
            rails[rail.name] = .object([
                "volts": .number(round2(rail.voltage)),
                "amps": .number(round2(rail.current)),
                "watts": .number(round2(rail.power)),
            ])
        }
        return [
            "body.board_temperature_f": .number(round1(report.boardTemperature)),
            "body.power": .object(rails),
        ]
    }

    /// The facts a motor report makes.
    static func facts(from report: MotorSensorReport) -> [String: WorldJSONValue] {
        var motors: [String: WorldJSONValue] = [:]
        var load = 0.0
        for motor in report.motors {
            motors[String(motor.motorNumber)] = .object([
                "position": .number(Double(motor.position)),
                "amps": .number(round2(motor.current)),
                "watts": .number(round2(motor.power)),
            ])
            load += motor.current
        }
        return [
            "body.motors": .object(motors),
            "body.motor_load_a": .number(round2(load)),
        ]
    }

    /// Whether a new value differs from the last one said by more than the thresholds.
    static func changed(
        _ predicate: String, from old: WorldJSONValue?, to new: WorldJSONValue,
        thresholds: BodyConfiguration.Thresholds
    ) -> Bool {
        guard let old else { return true }
        switch (predicate, old, new) {
        case ("body.board_temperature_f", .number(let a), .number(let b)):
            return abs(a - b) >= thresholds.temperatureF
        case ("body.motor_load_a", .number(let a), .number(let b)):
            return abs(a - b) >= thresholds.motorAmps
        case ("body.power", .object(let a), .object(let b)):
            return Set(a.keys) != Set(b.keys)
                || a.contains { rail, was in
                    numbersDiffer(was, b[rail], "volts", thresholds.volts)
                        || numbersDiffer(was, b[rail], "amps", thresholds.amps)
                        || numbersDiffer(was, b[rail], "watts", thresholds.watts)
                }
        case ("body.motors", .object(let a), .object(let b)):
            return Set(a.keys) != Set(b.keys)
                || a.contains { motor, was in
                    numbersDiffer(was, b[motor], "amps", thresholds.motorAmps)
                        || numbersDiffer(
                            was, b[motor], "position", Double(thresholds.motorPosition))
                }
        default:
            return old != new
        }
    }

    private static func numbersDiffer(
        _ a: WorldJSONValue, _ b: WorldJSONValue?, _ key: String, _ threshold: Double
    ) -> Bool {
        guard case .object(let x) = a, case .object(let y)? = b,
            case .number(let p)? = x[key], case .number(let q)? = y[key]
        else { return true }
        return abs(p - q) >= threshold
    }

    static func given(
        subject: EntityID, predicate: String, value: WorldJSONValue, validFor seconds: Int,
        at now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: eventType,
            occurredAt: now,
            source: EventSource(
                id: sourceID, kind: sourceKind,
                sourceEventID: "\(subject.rawValue):\(predicate):\(WorldJSON.timestamp(now))"),
            subjectIDs: [subject],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [
                "subject_id": .string(subject.rawValue),
                "predicate": .string(predicate),
                "value": value,
                "valid_for_seconds": .number(Double(seconds)),
            ])
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// What was last said for each bird and predicate, and when: the change detector.
struct BodyLedger: Sendable {
    private var last: [String: (value: WorldJSONValue, at: Date)] = [:]

    /// The facts worth saying now, given what was said before: a change past the threshold
    /// once the interval is up, or a steady value said again before the world forgets it.
    mutating func changes(
        for subject: EntityID, facts: [String: WorldJSONValue], now: Date,
        thresholds: BodyConfiguration.Thresholds, minimumInterval: TimeInterval,
        validFor: TimeInterval
    ) -> [(predicate: String, value: WorldJSONValue)] {
        var changes: [(String, WorldJSONValue)] = []
        for (predicate, value) in facts.sorted(by: { $0.key < $1.key }) {
            let key = "\(subject.rawValue)|\(predicate)"
            let previous = last[key]
            if let previous, now.timeIntervalSince(previous.at) < minimumInterval { continue }
            let nearlyForgotten =
                previous.map { now.timeIntervalSince($0.at) >= validFor * 0.8 } ?? false
            guard
                nearlyForgotten
                    || BodyFacts.changed(
                        predicate, from: previous?.value, to: value, thresholds: thresholds)
            else { continue }
            last[key] = (value, now)
            changes.append((predicate, value))
        }
        return changes
    }
}
