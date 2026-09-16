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
        "body.servos":
            "the bird's Dynamixel servos as they report themselves: for each, its temperature in degrees Fahrenheit, load, volts, position, and whether it is online",
        "body.servo_temperature_f":
            "the warmest of the bird's servos right now, in degrees Fahrenheit, and which one",
        "body.servos_offline":
            "servos that are not answering, by id; empty when every servo is online",
        "body.activity":
            "what the bird's body is doing right now, as the server runs it: idle, playing an animation, streaming, stopped, or disabled",
        "body.idle_enabled":
            "whether the bird's idle motion is switched on, so it moves a little between animations",
        "body.last_error":
            "the last thing that went wrong running the bird's body, as the server logged it, and when",
        "server.counters":
            "Creature Server's running totals since it started: frames, events, animations and sounds played, playlists, REST requests, websocket messages",
        "server.frames_per_second":
            "how fast Creature Server is ticking right now: frames sent to the birds per second",
        "server.animations_played":
            "how many animations Creature Server has played since it started",
        "server.sounds_played": "how many sounds Creature Server has played since it started",
    ]

    static let serverID = try! EntityID(validating: "thing:creature-server")

    /// The server's own facts, from its counters. Frames per second needs the counters before.
    static func facts(
        from counters: SystemCountersDTO, previous: (counters: SystemCountersDTO, at: Date)?,
        now: Date
    ) -> [String: WorldJSONValue] {
        var facts: [String: WorldJSONValue] = [
            "server.counters": .object([
                "frames": .number(Double(counters.totalFrames)),
                "events": .number(Double(counters.eventsProcessed)),
                "frames_streamed": .number(Double(counters.framesStreamed)),
                "dmx_events": .number(Double(counters.dmxEventsProcessed)),
                "animations_played": .number(Double(counters.animationsPlayed)),
                "sounds_played": .number(Double(counters.soundsPlayed)),
                "playlists_started": .number(Double(counters.playlistsStarted)),
                "rest_requests": .number(Double(counters.restRequestsProcessed)),
                "websocket_connections": .number(Double(counters.websocketConnectionsProcessed)),
                "websocket_messages_received": .number(Double(counters.websocketMessagesReceived)),
                "websocket_messages_sent": .number(Double(counters.websocketMessagesSent)),
            ]),
            "server.animations_played": .number(Double(counters.animationsPlayed)),
            "server.sounds_played": .number(Double(counters.soundsPlayed)),
        ]
        if let previous, counters.totalFrames >= previous.counters.totalFrames {
            let seconds = now.timeIntervalSince(previous.at)
            if seconds > 0 {
                let frames = Double(counters.totalFrames - previous.counters.totalFrames)
                facts["server.frames_per_second"] = .number((frames / seconds).rounded())
            }
        }
        return facts
    }

    /// A bird's facts from its runtime state: what it is doing, as the server runs it.
    static func facts(from runtime: CreatureRuntime) -> [String: WorldJSONValue] {
        var facts: [String: WorldJSONValue] = [:]
        if let activity = runtime.activity {
            facts["body.activity"] = .string(describe(activity))
        }
        if let idle = runtime.idleEnabled { facts["body.idle_enabled"] = .bool(idle) }
        if let error = runtime.lastError {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm a"
            facts["body.last_error"] = .string(
                "\(error.message) (at \(formatter.string(from: error.timestamp)))")
        }
        return facts
    }

    /// "playing an animation", "idle", "streaming", "stopped", "disabled".
    static func describe(_ activity: CreatureRuntimeActivity) -> String {
        switch activity.state {
        case .running:
            switch activity.reason {
            case .streaming?: return "streaming - being driven live"
            case .playlist?: return "playing an animation from a playlist"
            case .adHoc?: return "playing an ad-hoc animation - speaking, most likely"
            case .play?: return "playing an animation"
            case .idle?: return "idling - small movements between animations"
            default: return "running"
            }
        case .idle: return "idle"
        case .disabled: return "disabled"
        case .stopped: return "stopped"
        case .unknown: return "unknown"
        }
    }

    /// The facts a Dynamixel report makes: Beaky's kind of body, where each servo speaks for
    /// itself.
    static func facts(from report: DynamixelSensorReport) -> [String: WorldJSONValue] {
        var servos: [String: WorldJSONValue] = [:]
        var warmest: (id: String, temperature: Double)?
        var offline: [String] = []
        for servo in report.motors {
            let id = String(servo.dxlId)
            var reading: [String: WorldJSONValue] = [
                "temperature_f": .number(round1(servo.temperatureF)),
                "load": .number(Double(servo.presentLoad)),
                "volts": .number(round2(servo.voltageV)),
                "online": .bool(servo.online),
            ]
            if let position = servo.presentPosition {
                reading["position"] = .number(Double(position))
            }
            servos[id] = .object(reading)
            if servo.online, warmest.map({ servo.temperatureF > $0.temperature }) ?? true {
                warmest = (id, servo.temperatureF)
            }
            if !servo.online { offline.append(id) }
        }
        var facts: [String: WorldJSONValue] = [
            "body.servos": .object(servos),
            "body.servos_offline": .array(offline.sorted().map(WorldJSONValue.string)),
        ]
        if let warmest {
            facts["body.servo_temperature_f"] = .string(
                "\(round1(warmest.temperature).formatted(.number.precision(.fractionLength(0...1)))) °F, servo \(warmest.id)"
            )
        }
        return facts
    }

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
        case ("server.frames_per_second", .number(let a), .number(let b)):
            return abs(a - b) >= thresholds.framesPerSecond
        case ("server.counters", .object, .object):
            // Totals only ever climb; the interval, not a threshold, paces them.
            return old != new
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
        case ("body.servos", .object(let a), .object(let b)):
            return Set(a.keys) != Set(b.keys)
                || a.contains { servo, was in
                    numbersDiffer(was, b[servo], "temperature_f", thresholds.temperatureF)
                        || numbersDiffer(was, b[servo], "load", Double(thresholds.servoLoad))
                        || numbersDiffer(was, b[servo], "volts", thresholds.volts)
                        || numbersDiffer(
                            was, b[servo], "position", Double(thresholds.motorPosition))
                        || flagDiffers(was, b[servo], "online")
                }
        default:
            return old != new
        }
    }

    private static func flagDiffers(_ a: WorldJSONValue, _ b: WorldJSONValue?, _ key: String)
        -> Bool
    {
        guard case .object(let x) = a, case .object(let y)? = b else { return true }
        return x[key] != y[key]
    }

    private static func numbersDiffer(
        _ a: WorldJSONValue, _ b: WorldJSONValue?, _ key: String, _ threshold: Double
    ) -> Bool {
        guard case .object(let x) = a, case .object(let y)? = b else { return true }
        switch (x[key], y[key]) {
        case (.number(let p)?, .number(let q)?): return abs(p - q) >= threshold
        case (nil, nil): return false  // neither has it: nothing to compare
        default: return true
        }
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
