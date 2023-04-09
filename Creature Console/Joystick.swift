//
//  Joystick.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import GameController
import Logging

// TODO: This is a hack. Figure out something better, maybe. :)
var joystick0 = SixAxisJoystick()

func setupController() {
    
    let logger = Logger(label: "Joystick")
    
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
        if let controller = notification.object as? GCController {
            controller.extendedGamepad?.valueChangedHandler = { (gamepad, element) in
                if element == gamepad.leftThumbstick {
                    joystick0.axises[0].rawValue = gamepad.leftThumbstick.xAxis.value
                    joystick0.axises[1].rawValue = gamepad.leftThumbstick.yAxis.value
                }
                if element == gamepad.rightThumbstick {
                    joystick0.axises[2].rawValue = gamepad.rightThumbstick.xAxis.value
                    joystick0.axises[3].rawValue = gamepad.rightThumbstick.yAxis.value
                }
                if element == gamepad.rightTrigger {
                    joystick0.axises[5].rawValue = gamepad.rightTrigger.value
                }
                if element == gamepad.leftTrigger {
                    joystick0.axises[4].rawValue = gamepad.leftTrigger.value
                }
                
                // TODO: Debug dump
                print("[ \(joystick0.axises[0].value), \(joystick0.axises[1].value), \(joystick0.axises[2].value), \(joystick0.axises[3].value), \(joystick0.axises[4].value), \(joystick0.axises[5].value) ]")
                
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
