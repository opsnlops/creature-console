//
//  SixAxisJoystick.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import Foundation
import GameController
import Logging
import Combine

class Axis : ObservableObject, CustomStringConvertible {
    var axisType : AxisType = .gamepad
    @Published var name: String = ""
    @Published var value: UInt8 = 127
    @Published var rawValue: Float = 0 {
        didSet {
            
            var mappedvalue = Float(0.0)
            
            switch(axisType) {
            case(.gamepad):
                // The raw value is a value of -1.0 to 1.0, where the center is 0. Let's map this to a value that we normally use on our creature joysticks
                mappedvalue = Float(UInt8.max) * Float((rawValue + 1.0)/2)
                
            default:
                mappedvalue = Float(UInt8.max) * Float(rawValue)
            }
  
            value = UInt8(round(mappedvalue))
        }
    }
    
    var description: String {
        return String(value)
    }
    
    enum AxisType : Int, CustomStringConvertible {
      case gamepad = 0
      case trigger = 1
        
        var description: String {
            switch self {
            case .gamepad:
                return "Gamepad"
            case .trigger:
                return "Trigger"
            }
        }
    }
}

class SixAxisJoystick : ObservableObject {
    @Published var axises : [Axis]
    var controller : GCController?
    let objectWillChange = ObservableObjectPublisher()
    let logger = Logger(label: "SixAxisJoystick")
    
#if os(iOS)
    var virtualJoysick = VirtualJoystick()
    var virtualJoystickConnected = false
#endif
    
    var vendor : String {
        controller?.vendorName ?? "Unknown"
    }
    
    init() {
        self.axises = []
        
        for _ in 0...5 {
            self.axises.append(Axis())
        }
        
        // Axies 4 and 5 are triggers
        self.axises[4].axisType = .trigger
        self.axises[5].axisType = .trigger
        self.axises[4].value = 0
        self.axises[5].value = 0
    }
    
    var axisValues: [UInt8] {
        return axises.map { $0.value }
    }
    
    func showVirtualJoystickIfNeeded() {
        
        #if os(iOS)
        if GCController.controllers().isEmpty {
            logger.info("creating virtual joystick")
            virtualJoysick.create()
            virtualJoysick.connect()
            virtualJoystickConnected = true
        }
        #endif
        
    }
    
    func removeVirtualJoystickIfNeeded() {
        #if os(iOS)
        if virtualJoystickConnected {
            virtualJoysick.disconnect()
            virtualJoystickConnected = false
            logger.info("disconnecting virtual joystick")
        }
        #endif
    }
    
    
    func poll() {
        
        if let joystick = controller?.extendedGamepad {
            
            var didChange = false
            
            if axises[0].rawValue != joystick.leftThumbstick.xAxis.value {
                axises[0].rawValue = joystick.leftThumbstick.xAxis.value
                didChange = true
            }
            
            if axises[1].rawValue != joystick.leftThumbstick.yAxis.value {
                axises[1].rawValue = joystick.leftThumbstick.yAxis.value
                didChange = true
            }
            
            if axises[2].rawValue != joystick.rightThumbstick.xAxis.value {
                axises[2].rawValue = joystick.rightThumbstick.xAxis.value
                didChange = true
            }
            
            if axises[3].rawValue != joystick.rightThumbstick.yAxis.value {
                axises[3].rawValue = joystick.rightThumbstick.yAxis.value
                didChange = true
            }
            
            if axises[4].rawValue != joystick.leftTrigger.value {
                axises[4].rawValue = joystick.leftTrigger.value
                didChange = true
            }
            
            if axises[5].rawValue != joystick.rightTrigger.value {
                axises[5].rawValue = joystick.rightTrigger.value
                didChange = true
            }
            
   
            logger.debug("joystick polling done")
       
            if didChange {
                objectWillChange.send()
            }
        }
        else {
            logger.info("skipping polling because not extended gamepad")
        }
        
    }
    
}


extension SixAxisJoystick {
    static func mock() -> SixAxisJoystick {
        let joystick = SixAxisJoystick()
        
        for axis in joystick.axises {
            axis.value = UInt8(arc4random_uniform(UInt32(UInt8.max)))
        }
        
        return joystick
    }
}
