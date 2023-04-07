//
//  Joystick.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import GameController
import Logging

func setupController() {
    
    let logger = Logger(label: "Joystick")
    
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
        if let controller = notification.object as? GCController {
            controller.extendedGamepad?.valueChangedHandler = { (gamepad, element) in
                if element == gamepad.leftThumbstick {
                    let x = gamepad.leftThumbstick.xAxis.value
                    let y = gamepad.leftThumbstick.yAxis.value
                    logger.debug("Left Thumbstick: x: \(x), y: \(y)")
                }
                if element == gamepad.rightThumbstick {
                    let x = gamepad.rightThumbstick.xAxis.value
                    let y = gamepad.rightThumbstick.yAxis.value
                    logger.debug("Right Thumbstick: x: \(x), y: \(y)")
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
