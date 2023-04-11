//
//  VirtualJoystick.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import Foundation
import GameController
import Logging


#if os(iOS)


class VirtualJoystick {
    
    var virualConfiguration : GCVirtualController.Configuration
    var virtualController : GCVirtualController?
    
    let logger = Logger(label: "VirtualJoystick")
    
    
    init() {
        virualConfiguration = GCVirtualController.Configuration()
        virualConfiguration.elements = [GCInputLeftThumbstick,
                                             GCInputRightThumbstick,
                                             GCInputLeftTrigger,
                                             GCInputRightTrigger]
    }
    
    func create() {
        
        virtualController = GCVirtualController(configuration: self.virualConfiguration)
        logger.info("created a virtual joystick EMPTY")
        
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
