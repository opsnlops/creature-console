//
//  SixAxisJoystick.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import Foundation

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
    
}
