import Common
import Foundation
import OSLog
import SwiftUI


class StatusLightsManager: ObservableObject {
    static let shared = StatusLightsManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "StatusLightsManager")

    @Published var running: Bool = false
    @Published var dmx: Bool = false
    @Published var streaming: Bool = false
    @Published var animationPlaying: Bool = false

    private init() {}

    func update(from dto: VirtualStatusLightsDTO) {

        /**
         Only update the things that change to keep the number of change messages to only what's actually needed
         */

        if dto.running != self.running {
            DispatchQueue.main.async {
                self.running = dto.running
            }

            logger.info("set the running light to \(dto.running ? "on" : "off")")
        }

        if dto.dmx != self.dmx {
            DispatchQueue.main.async {
                self.dmx = dto.dmx
            }

            logger.info("set the dmx light to \(dto.dmx ? "on" : "off")")
        }

        if dto.streaming != self.streaming {
            DispatchQueue.main.async {
                self.streaming = dto.streaming
            }

            logger.info("set the streaming light to \(dto.streaming ? "on" : "off")")
        }

        if dto.animation_playing != self.animationPlaying {
            DispatchQueue.main.async {
                self.animationPlaying = dto.animation_playing
            }

            logger.info("set the animation playing light to \(dto.animation_playing ? "on" : "off")")
        }
    }

}
