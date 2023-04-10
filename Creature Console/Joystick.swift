//
//  Joystick.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import GameController
import Logging


func setupController(joystick: SixAxisJoystick) {
    
    let logger = Logger(label: "Joystick")
    
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
        if let controller = notification.object as? GCController {
            controller.extendedGamepad?.valueChangedHandler = { (gamepad, element) in
                if element == gamepad.leftThumbstick {
                    joystick.axises[0].rawValue = gamepad.leftThumbstick.xAxis.value
                    joystick.axises[1].rawValue = gamepad.leftThumbstick.yAxis.value
                    logger.debug("leftThumbStick changed")
                }
                if element == gamepad.rightThumbstick {
                    joystick.axises[2].rawValue = gamepad.rightThumbstick.xAxis.value
                    joystick.axises[3].rawValue = gamepad.rightThumbstick.yAxis.value
                    logger.debug("rightThumbstick changed")
                }
                if element == gamepad.rightTrigger {
                    joystick.axises[5].rawValue = gamepad.rightTrigger.value
                    logger.debug("rightTrigger changed")
                }
                if element == gamepad.leftTrigger {
                    joystick.axises[4].rawValue = gamepad.leftTrigger.value
                    logger.debug("leftTrigger changed")
                }
            }
        }
    }
    
    NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { notification in
        logger.info("Controller disconnected")
    }
    
    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    })
}
