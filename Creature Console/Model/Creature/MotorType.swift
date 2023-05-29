//
//  MotorType.swift
//  Creature Console
//
//  Created by April White on 5/27/23.
//

import Foundation


enum MotorType : Int, CustomStringConvertible {
  case servo = 0
  case stepper = 1
    
    var description: String {
        switch self {
        case .servo:
            return "Servo"
        case .stepper:
            return "Stepper"
        }
    }
}

