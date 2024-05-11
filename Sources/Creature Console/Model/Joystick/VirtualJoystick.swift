

import Foundation
import GameController
import OSLog
import Common


#if os(iOS)


class VirtualJoystick {
    
    var virualConfiguration : GCVirtualController.Configuration
    var virtualController : GCVirtualController?
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "VirtualJoystick")
    
    
    init() {
        virualConfiguration = GCVirtualController.Configuration()
        virualConfiguration.elements = [GCInputLeftThumbstick,
                                        GCInputRightThumbstick,
                                        GCInputLeftTrigger,
                                        GCInputRightTrigger,
                                        GCInputButtonX]
    }
    
    func create() {
        
        virtualController = GCVirtualController(configuration: self.virualConfiguration)
        logger.info("created a virtual joystick")
        
    }
    
    func connect() {
    
        logger.info("connecting virtual joystick");
        virtualController?.connect()
        
    }
    
    func disconnect() {
        
        logger.info("disconnecting virtual joystick")
        virtualController?.disconnect()
    }
    
}


#endif
