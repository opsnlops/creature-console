import Common
import Foundation

/// A simple `MessageProcessor` that prints things to the screen for debugging
class CLIMessageProcessor: MessageProcessor {

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        print(
            "[BOARD_SENSORS] Creature: \(boardSensorReport.creatureId), board temperature: \(boardSensorReport.boardTemperature)F"
        )

        let headers = ["Name", "Voltage", "Current", "Power"]
        var rows = [[String]]()

        for sensor in boardSensorReport.powerReports {
            let row = [
                String(sensor.name),
                String(sensor.voltage),
                String(sensor.current),
                String(sensor.power),
            ]
            rows.append(row)
        }
        printTable(headers: headers, rows: rows)
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        print(
            "[CACHE INVALIDATION] the server has requested that we invalidate the \(cacheInvalidation.cacheType.description) cache"
        )
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        print(
            "[EMERGENCY STOP] [\(TimeHelper.formatToLocalTime(emergencyStop.timestamp))] \(emergencyStop.reason)"
        )
    }

    func processLog(_ logItem: ServerLogItem) {
        print(
            "[LOG] [\(TimeHelper.formatToLocalTime(logItem.timestamp))] [\(logItem.level)] \(logItem.message)"
        )
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) {
        print(
            "[MOTOR_SENSORS] Creature: \(motorSensorReport.creatureId)"
        )

        let headers = ["Number", "Position", "Voltage", "Current", "Power"]
        var rows = [[String]]()

        for sensor in motorSensorReport.motors {
            let row = [
                String(sensor.motorNumber),
                String(sensor.position),
                String(sensor.voltage),
                String(sensor.current),
                String(sensor.power),
            ]
            rows.append(row)
        }
        printTable(headers: headers, rows: rows)
    }

    func processNotice(_ notice: Notice) {
        print("[NOTICE] [\(TimeHelper.formatToLocalTime(notice.timestamp))] \(notice.message)")
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        print(
            "[PLAYLIST UPDATE] universe \(playlistStatus.universe), playing \(playlistStatus.playing), playlist \(playlistStatus.playlist), currentAnimation: \(playlistStatus.currentAnimation)"
        )
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        print(
            "[STATUS LIGHTS] running: \(statusLights.running ? "on" : "off"), streaming: \(statusLights.streaming ? "on" : "off"), DMX: \(statusLights.dmx ? "on" : "off"), animation_playing: \(statusLights.animation_playing ? "on" : "off")"
        )
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        print(
            "[COUNTERS] Server is on frame \(counters.totalFrames)! \(counters.framesStreamed) frames have been streamed."
        )
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        print(
            "[WATCHDOG WARNING] [\(TimeHelper.formatToLocalTime(watchdogWarning.timestamp))] \(watchdogWarning.warningType): \(watchdogWarning.currentValue)/\(watchdogWarning.threshold)"
        )
    }
}
