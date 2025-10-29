import Foundation
import Logging

public actor WebSocketStateManager {
    public static let shared = WebSocketStateManager()

    private let logger = Logger(label: "io.opsnlops.CreatureController.WebSocketStateManager")

    private var currentState = WebSocketConnectionState.disconnected
    private var continuations: [UUID: AsyncStream<WebSocketConnectionState>.Continuation] = [:]

    public var stateUpdates: AsyncStream<WebSocketConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            logger.debug(
                "WebSocketStateManager: New subscriber \(id) - seeding with state: \(self.currentState.description)"
            )

            // Send current state immediately to new subscriber
            continuation.yield(self.currentState)

            continuation.onTermination = { @Sendable _ in
                Task { [id] in
                    await self.removeContinuation(id)
                }
            }
        }
    }

    private init() {
        logger.info("WebSocketStateManager created")
    }

    private func removeContinuation(_ id: UUID) {
        logger.debug("WebSocketStateManager: Removing subscriber \(id)")
        continuations.removeValue(forKey: id)
    }

    public func setState(_ state: WebSocketConnectionState) {
        logger.info("WebSocketStateManager: Setting state to \(state.description)")
        self.currentState = state
        self.publishState()
    }

    private func publishState() {
        logger.debug(
            "WebSocketStateManager: Broadcasting state (\(self.currentState.description)) to \(self.continuations.count) subscribers"
        )
        for continuation in self.continuations.values {
            continuation.yield(self.currentState)
        }
    }

    public var getCurrentState: WebSocketConnectionState {
        return self.currentState
    }
}
