import Foundation
import Logging

extension CreatureServerClient {

    public func streamFrame(streamFrameData: StreamFrameData) async -> Result<String, ServerError> {

        // Make sure we're connected before we try this
        guard let ws = webSocketClient, await ws.isWebSocketConnected else {
            return .failure(.websocketError("Web Socket is not connected"))
        }

        logger.trace("streaming a frame to \(streamFrameData.creatureId)")

        do {
            // Build this frame
            let frameJSON = try WebSocketMessageBuilder.createMessage(
                type: .streamFrame, payload: streamFrameData)

            // A failed send is the caller's business — swallowing it here left the
            // console blind to streaming failures (issue #50).
            switch await self.sendMessage(frameJSON) {
            case .success:
                return .success("Frame streamed")
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            return .failure(.serverError("Unable to encode frame: \(error.localizedDescription)"))
        }
    }
}
