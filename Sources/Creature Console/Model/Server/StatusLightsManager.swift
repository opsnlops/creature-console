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

    private var continuations: [UUID: AsyncStream<StatusLightsState>.Continuation] = [:]

    var stateUpdates: AsyncStream<StatusLightsState> {
        AsyncStream { continuation in
            let id = UUID()
            // Register and seed on the actor
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private init() {
        // Initial state will be published on first access to stateUpdates
    }

    private func currentSnapshot() -> StatusLightsState {
        StatusLightsState(
            running: running,
            dmx: dmx,
            streaming: streaming,
            animationPlaying: animationPlaying
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<StatusLightsState>.Continuation) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        logger.debug("StatusLightsManager: Broadcasting state (running: \(self.running), dmx: \(self.dmx), streaming: \(self.streaming), animationPlaying: \(self.animationPlaying))")
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
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
