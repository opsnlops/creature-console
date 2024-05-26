import Common
import Foundation

/// A simple `MessageProcessor` that prints things to the screen for debugging
class CLIMessageProcessor: MessageProcessor {

    func processNotice(_ notice: Notice) {
        print("[NOTICE] [\(TimeHelper.formatToLocalTime(notice.timestamp))] \(notice.message)")
    }

    func processLog(_ logItem: ServerLogItem) {
        print(
            "[LOG] [\(TimeHelper.formatToLocalTime(logItem.timestamp))] [\(logItem.level)] \(logItem.message)"
        )
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        print(
            "[COUNTERS] Server is on frame \(counters.totalFrames)! \(counters.framesStreamed) frames have been streamed."
        )
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        print(
            "[STATUS LIGHTS] running: \(statusLights.running ? "on" : "off"), streaming: \(statusLights.streaming ? "on" : "off"), DMX: \(statusLights.dmx ? "on" : "off"), animation_playing: \(statusLights.animation_playing ? "on" : "off")"
        )
    }
}
