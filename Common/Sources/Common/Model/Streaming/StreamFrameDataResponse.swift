
import Foundation
import Logging

/**
 This is a vesion of the StreamFrameDataResponse RPC object
 */
public struct StreamFrameDataResponse {
    
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.StreamFrameDataResponse")

    var framesProcessed : UInt32
    var message : String
//     
//    init(framesProcessed: UInt32, message: String) {
//        self.framesProcessed = framesProcessed
//        self.message = message
//        logger.debug("Created a new StreamFrameDataResponse from init()")
//    }
//    
//    // Creates a new instance from a ProtoBuf object
//    init(serverStreamFrameDataResponse: Server_StreamFrameDataResponse) {
//        
//        self.init(framesProcessed: serverStreamFrameDataResponse.framesProcessed,
//                  message: serverStreamFrameDataResponse.message)
//    }
}


extension StreamFrameDataResponse {
    
    public static func mock() -> StreamFrameDataResponse {

        let framesProcessed = UInt32.random(in: 1...1000)
        let message = "Mock response received successfully!"
        
        return StreamFrameDataResponse(framesProcessed: framesProcessed, message: message)
    }
}
