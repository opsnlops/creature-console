//
//  Motor.swift
//  Creature Console
//
//  Created by April White on 5/27/23.
//

import Foundation


struct Motor : Identifiable, Hashable, Equatable {
    let id : Data
    var name : String
    var type : MotorType = MotorType.servo
    var number : UInt32 = 0
    var maxValue : UInt32 = 0
    var minValue : UInt32 = 0
    var smoothingValue : Double = 0.0
    
    init(id: Data, name: String, type: MotorType, number: UInt32, maxValue: UInt32, minValue: UInt32, smoothingValue: Double) {
        self.id = id
        self.name = name
        self.type = type
        self.number = number
        self.maxValue = maxValue
        self.minValue = minValue
        self.smoothingValue = smoothingValue
    }
    
    // Little hepler that generates a random ID
    init(name: String, type: MotorType, number: UInt32, maxValue: UInt32, minValue: UInt32, smoothingValue: Double) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, type: type, number: number, maxValue: maxValue, minValue: minValue, smoothingValue: smoothingValue)
    }
    
    // Implement the hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(type)
        hasher.combine(number)
        hasher.combine(maxValue)
        hasher.combine(minValue)
        hasher.combine(smoothingValue)
    }

    // Implement the == operator
    static func ==(lhs: Motor, rhs: Motor) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.type == rhs.type &&
               lhs.number == rhs.number &&
               lhs.maxValue == rhs.maxValue &&
               lhs.minValue == rhs.minValue &&
               lhs.smoothingValue == rhs.smoothingValue
    }
}

