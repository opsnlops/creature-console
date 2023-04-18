//
//  Joystick.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import GameController
import Logging


func registerJoystickHandlers(eventLoop: EventLoop) {
    
    let logger = Logger(label: "Joystick")

    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
        logger.info("got a .GCControllerDidConnect notification")
        if let controller = notification.object as? GCController {
            
            if ((controller.extendedGamepad) != nil) {
                logger.debug("extended joystick connected, woot")
                eventLoop.joystick0.controller = controller
            }
        }
    }
    
    NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { notification in
        logger.info("Controller disconnected")
        eventLoop.joystick0.controller = nil
    }
    
    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    })
}
