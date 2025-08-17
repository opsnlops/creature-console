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

            // Send the encoded JSON frame
            let result = await self.sendMessage(frameJSON)

            switch result {
            case .failure(let error):
                print("Error sending frame: \(error.localizedDescription)")
            default:
                break
            }
        } catch (let error) {
            return .failure(.serverError("Unable to send frame: \(error.localizedDescription)"))
        }

        return .success("Frame streamed")

    }
}
