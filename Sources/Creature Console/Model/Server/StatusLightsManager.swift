import Common
import Foundation
import OSLog
import SwiftUI

struct StatusLightsState: Sendable {
    let running: Bool
    let dmx: Bool
    let streaming: Bool
    let animationPlaying: Bool
}

actor StatusLightsManager {
    static let shared = StatusLightsManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "StatusLightsManager")

    private var running: Bool = false
    private var dmx: Bool = false
    private var streaming: Bool = false
    private var animationPlaying: Bool = false

    private let (stateStream, stateContinuation) = AsyncStream.makeStream(of: StatusLightsState.self)
    var stateUpdates: AsyncStream<StatusLightsState> { 
        publishState() // Ensure initial state is published
        return stateStream 
    }

    private init() {
        // Initial state will be published on first access to stateUpdates
    }

    private func publishState() {
        let currentState = StatusLightsState(
            running: running,
            dmx: dmx,
            streaming: streaming,
            animationPlaying: animationPlaying
        )
        stateContinuation.yield(currentState)
    }

    func update(from dto: VirtualStatusLightsDTO) {
        var changed = false

        if dto.running != self.running {
            self.running = dto.running
            logger.info("set the running light to \(dto.running ? "on" : "off")")
            changed = true
        }

        if dto.dmx != self.dmx {
            self.dmx = dto.dmx
            logger.info("set the dmx light to \(dto.dmx ? "on" : "off")")
            changed = true
        }

        if dto.streaming != self.streaming {
            self.streaming = dto.streaming
            logger.info("set the streaming light to \(dto.streaming ? "on" : "off")")
            changed = true
        }

        if dto.animation_playing != self.animationPlaying {
            self.animationPlaying = dto.animation_playing
            logger.info(
                "set the animation playing light to \(dto.animation_playing ? "on" : "off")")
            changed = true
        }

        if changed {
            publishState()
        }
    }
}
