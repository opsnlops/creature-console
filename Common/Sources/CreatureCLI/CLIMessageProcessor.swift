import ArgumentParser
import Common
import Foundation

/// A simple `MessageProcessor` that prints things to the screen for debugging
final class CLIMessageProcessor: MessageProcessor {

    enum MessageType: String, CaseIterable, ExpressibleByArgument {
        case boardSensors = "board-sensors"
        case cacheInvalidation = "cache-invalidation"
        case emergencyStop = "emergency-stop"
        case log = "log"
        case motorSensors = "motor-sensors"
        case notice = "notice"
        case playlistStatus = "playlist-status"
        case statusLights = "status-lights"
        case systemCounters = "system-counters"
        case watchdogWarning = "watchdog-warning"
        case jobProgress = "job-progress"
        case jobComplete = "job-complete"

        static var helpText: String {
            Self.allCases.map { $0.rawValue }.sorted().joined(separator: ", ")
        }
    }

    enum OutputFormat {
        case text
        case json
    }

    private static let colorMap: [MessageType: String] = [
        .boardSensors: "33",
        .cacheInvalidation: "35",
        .emergencyStop: "31",
        .log: "37",
        .motorSensors: "36",
        .notice: "32",
        .playlistStatus: "34",
        .statusLights: "96",
        .systemCounters: "95",
        .watchdogWarning: "91",
        .jobProgress: "93",
        .jobComplete: "92",
    ]

    private static let logLevelColorMap: [ServerLogLevel: String] = [
        .trace: "90",
        .debug: "36",
        .info: "32",
        .warn: "33",
        .error: "31",
        .critical: "35",
        .off: "37",
        .unknown: "37",
    ]

    private let hiddenTypes: Set<MessageType>
    private let allowedTypes: Set<MessageType>?
    private let useColor: Bool
    private let outputFormat: OutputFormat
    private let jsonEncoder: JSONEncoder?

    init(
        hiddenTypes: Set<MessageType> = [],
        allowedTypes: Set<MessageType>? = nil,
        outputFormat: OutputFormat = .text,
        useColor: Bool = true
    ) {
        self.hiddenTypes = hiddenTypes
        self.allowedTypes = allowedTypes
        self.outputFormat = outputFormat
        self.useColor = useColor && outputFormat == .text
        if outputFormat == .json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.withoutEscapingSlashes]
            self.jsonEncoder = encoder
        } else {
            self.jsonEncoder = nil
        }
    }

    private func shouldPrint(_ type: MessageType) -> Bool {
        if let allowedTypes, !allowedTypes.contains(type) {
            return false
        }
        return !hiddenTypes.contains(type)
    }

    private func colorCode(for type: MessageType) -> String? {
        guard useColor else { return nil }
        return Self.colorMap[type]
    }

    private func colorize(_ type: MessageType, message: String) -> String {
        guard let code = colorCode(for: type) else { return message }
        return "\u{001B}[\(code)m\(message)\u{001B}[0m"
    }

    private func printLine(_ type: MessageType, _ message: String) {
        print(colorize(type, message: message))
    }

    private func buildLogLine(for logItem: ServerLogItem) -> String {
        let timestamp = TimeHelper.formatToLocalTime(logItem.timestamp)

        let basePrefix: String
        let baseSuffix: String
        if let code = colorCode(for: .log) {
            basePrefix = "\u{001B}[\(code)m"
            baseSuffix = "\u{001B}[0m"
        } else {
            basePrefix = ""
            baseSuffix = ""
        }

        let levelEnum = ServerLogLevel(from: logItem.level)
        let levelText = levelEnum.description.uppercased()
        let levelPrefix: String
        if useColor, let code = Self.logLevelColorMap[levelEnum] {
            levelPrefix = "\u{001B}[\(code)m"
        } else {
            levelPrefix = ""
        }
        let levelSuffix: String
        if levelPrefix.isEmpty {
            levelSuffix = ""
        } else if basePrefix.isEmpty {
            levelSuffix = "\u{001B}[0m"
        } else {
            levelSuffix = basePrefix
        }

        let levelSegment = "\(levelPrefix)\(levelText)\(levelSuffix)"

        return "\(basePrefix)[LOG] [\(timestamp)] [\(levelSegment)] \(logItem.message)\(baseSuffix)"
    }

    private func emitJSON<Payload: Encodable>(type: MessageType, payload: Payload) {
        guard let encoder = jsonEncoder else { return }
        let envelope = JSONEnvelope(type: type.rawValue, payload: payload)
        do {
            let data = try encoder.encode(envelope)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } catch {
            let fallback =
                "{\"type\":\"error\",\"message\":\"failed to encode JSON output\",\"reason\":\"\(error)\"}"
            print(fallback)
        }
    }

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        guard shouldPrint(.boardSensors) else { return }
        if outputFormat == .json {
            emitJSON(type: .boardSensors, payload: boardSensorReport)
            return
        }
        printLine(
            .boardSensors,
            "[BOARD_SENSORS] Creature: \(boardSensorReport.creatureId), board temperature: \(boardSensorReport.boardTemperature)F"
        )

        let headers = ["Name", "Voltage", "Current", "Power"]
        printTable(
            boardSensorReport.powerReports,
            columns: [
                TableColumn(title: headers[0], valueProvider: { String($0.name) }),
                TableColumn(title: headers[1], valueProvider: { String($0.voltage) }),
                TableColumn(title: headers[2], valueProvider: { String($0.current) }),
                TableColumn(title: headers[3], valueProvider: { String($0.power) }),
            ],
            colorCode: colorCode(for: .boardSensors)
        )
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        guard shouldPrint(.cacheInvalidation) else { return }
        if outputFormat == .json {
            emitJSON(type: .cacheInvalidation, payload: cacheInvalidation)
            return
        }
        printLine(
            .cacheInvalidation,
            "[CACHE INVALIDATION] the server has requested that we invalidate the \(cacheInvalidation.cacheType.description) cache"
        )
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        guard shouldPrint(.emergencyStop) else { return }
        if outputFormat == .json {
            emitJSON(type: .emergencyStop, payload: emergencyStop)
            return
        }
        printLine(
            .emergencyStop,
            "[EMERGENCY STOP] [\(TimeHelper.formatToLocalTime(emergencyStop.timestamp))] \(emergencyStop.reason)"
        )
    }

    func processLog(_ logItem: ServerLogItem) {
        guard shouldPrint(.log) else { return }
        if outputFormat == .json {
            emitJSON(type: .log, payload: LogPayload(logItem))
            return
        }
        print(buildLogLine(for: logItem))
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) {
        guard shouldPrint(.motorSensors) else { return }
        if outputFormat == .json {
            emitJSON(type: .motorSensors, payload: motorSensorReport)
            return
        }
        printLine(.motorSensors, "[MOTOR_SENSORS] Creature: \(motorSensorReport.creatureId)")

        let headers = ["Number", "Position", "Voltage", "Current", "Power"]
        printTable(
            motorSensorReport.motors,
            columns: [
                TableColumn(title: headers[0], valueProvider: { String($0.motorNumber) }),
                TableColumn(title: headers[1], valueProvider: { String($0.position) }),
                TableColumn(title: headers[2], valueProvider: { String($0.voltage) }),
                TableColumn(title: headers[3], valueProvider: { String($0.current) }),
                TableColumn(title: headers[4], valueProvider: { String($0.power) }),
            ],
            colorCode: colorCode(for: .motorSensors)
        )
    }

    func processNotice(_ notice: Notice) {
        guard shouldPrint(.notice) else { return }
        if outputFormat == .json {
            emitJSON(type: .notice, payload: notice)
            return
        }
        printLine(
            .notice,
            "[NOTICE] [\(TimeHelper.formatToLocalTime(notice.timestamp))] \(notice.message)")
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        guard shouldPrint(.playlistStatus) else { return }
        if outputFormat == .json {
            emitJSON(type: .playlistStatus, payload: playlistStatus)
            return
        }
        printLine(
            .playlistStatus,
            "[PLAYLIST UPDATE] universe \(playlistStatus.universe), playing \(playlistStatus.playing), playlist \(playlistStatus.playlist), currentAnimation: \(playlistStatus.currentAnimation)"
        )
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        guard shouldPrint(.statusLights) else { return }
        if outputFormat == .json {
            emitJSON(type: .statusLights, payload: statusLights)
            return
        }
        let formatState: (Bool) -> String = { $0 ? "on" : "off" }
        let message =
            "[STATUS LIGHTS] running: \(formatState(statusLights.running)), "
            + "streaming: \(formatState(statusLights.streaming)), "
            + "DMX: \(formatState(statusLights.dmx)), "
            + "animation_playing: \(formatState(statusLights.animation_playing))"
        printLine(.statusLights, message)
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        guard shouldPrint(.systemCounters) else { return }
        if outputFormat == .json {
            emitJSON(type: .systemCounters, payload: counters)
            return
        }
        printLine(
            .systemCounters,
            "[COUNTERS] Server is on frame \(counters.totalFrames)! \(counters.framesStreamed) frames have been streamed."
        )
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        guard shouldPrint(.watchdogWarning) else { return }
        if outputFormat == .json {
            emitJSON(type: .watchdogWarning, payload: watchdogWarning)
            return
        }
        printLine(
            .watchdogWarning,
            "[WATCHDOG WARNING] [\(TimeHelper.formatToLocalTime(watchdogWarning.timestamp))] \(watchdogWarning.warningType): \(watchdogWarning.currentValue)/\(watchdogWarning.threshold)"
        )
    }

    func processJobProgress(_ jobProgress: JobProgress) {
        guard shouldPrint(.jobProgress) else { return }
        if outputFormat == .json {
            emitJSON(type: .jobProgress, payload: jobProgress)
            return
        }

        var parts: [String] = [
            "[JOB PROGRESS]",
            "id: \(jobProgress.jobId)",
            "type: \(jobProgress.jobType.rawValue)",
            "status: \(jobProgress.status.rawValue)",
        ]

        if let value = jobProgress.progress {
            let percentage = value * 100.0
            parts.append(String(format: "progress: %.1f%%", percentage))
        }

        if let lipDetails: LipSyncJobDetails = jobProgress.decodeDetails(as: LipSyncJobDetails.self)
        {
            parts.append("sound: \(lipDetails.soundFile)")
            if lipDetails.allowOverwrite {
                parts.append("(overwrite)")
            }
        }

        if jobProgress.jobType == .animationLipSync,
            let animationDetails: AnimationLipSyncJobDetails = jobProgress.decodeDetails(
                as: AnimationLipSyncJobDetails.self)
        {
            parts.append("animation: \(animationDetails.animationId)")
        }

        printLine(.jobProgress, parts.joined(separator: " "))
    }

    func processJobComplete(_ jobComplete: JobCompletion) {
        guard shouldPrint(.jobComplete) else { return }
        if outputFormat == .json {
            emitJSON(type: .jobComplete, payload: jobComplete)
            return
        }

        var parts: [String] = [
            "[JOB COMPLETE]",
            "id: \(jobComplete.jobId)",
            "type: \(jobComplete.jobType.rawValue)",
            "status: \(jobComplete.status.rawValue)",
        ]

        if let lipDetails: LipSyncJobDetails = jobComplete.decodeDetails(as: LipSyncJobDetails.self)
        {
            parts.append("sound: \(lipDetails.soundFile)")
        }

        if jobComplete.jobType == .animationLipSync,
            let animationDetails: AnimationLipSyncJobDetails = jobComplete.decodeDetails(
                as: AnimationLipSyncJobDetails.self)
        {
            parts.append("animation: \(animationDetails.animationId)")
        }

        if jobComplete.status == .completed {
            if let payloadSize = jobComplete.result?.count {
                parts.append("payload: \(payloadSize) bytes")
            }
        } else if let statusMessage = jobComplete.result, !statusMessage.isEmpty {
            parts.append("result: \(statusMessage)")
        }

        if
            (jobComplete.jobType == .adHocSpeech || jobComplete.jobType == .adHocSpeechPrepare),
            let adHocResult: AdHocSpeechJobResult = jobComplete.decodeResult(as: AdHocSpeechJobResult.self)
        {
            parts.append("animation: \(adHocResult.animationId)")
            if let universe = adHocResult.universe {
                parts.append("universe: \(universe)")
            }
            if !adHocResult.playbackTriggered {
                parts.append("(awaiting playback)")
            }
        }

        if jobComplete.jobType == .animationLipSync,
            let result: AnimationLipSyncJobResult = jobComplete.decodeResult(as: AnimationLipSyncJobResult.self)
        {
            parts.append("tracks: \(result.updatedTracks)")
        }

        printLine(.jobComplete, parts.joined(separator: " "))
    }
}

private struct JSONEnvelope<Payload: Encodable>: Encodable {
    let type: String
    let payload: Payload
}

private struct LogPayload: Encodable {
    let timestamp: Date
    let level: String
    let level_description: String
    let message: String
    let logger_name: String
    let thread_id: UInt32

    init(_ item: ServerLogItem) {
        timestamp = item.timestamp
        level = item.level
        level_description = ServerLogLevel(from: item.level).description
        message = item.message
        logger_name = item.logger_name
        thread_id = item.thread_id
    }
}
