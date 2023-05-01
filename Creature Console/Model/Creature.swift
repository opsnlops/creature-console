//
//  Creature.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import Logging


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

class CreatureIdentifier : ObservableObject, Identifiable, CustomStringConvertible {
    let id : Data
    let name : String
    
    init(id: Data, name: String) {
        self.id = id
        self.name = name
    }
    
    var description: String {
        return self.name
    }
}

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


/**
 This is a localized view of a Creature
 
 We need this wrapper so we can make the object observable
 */
class Creature : ObservableObject, Identifiable, Hashable, Equatable {
    private let logger = Logger(label: "Creature")
    var id : Data
    @Published var name : String
    @Published var lastUpdated : Date
    @Published var sacnIP : String
    @Published var universe : UInt32
    @Published var dmxBase : UInt32
    @Published var numberOfMotors : UInt32
    @Published var motors : [Motor]
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded

    init(id: Data, name: String, lastUpdated: Date, sacnIP: String, universe: UInt32, dmxBase: UInt32, numberOfMotors: UInt32) {
        self.id = id
        self.name = name
        self.lastUpdated = lastUpdated
        self.sacnIP = sacnIP
        self.universe = universe
        self.dmxBase = dmxBase
        self.numberOfMotors = numberOfMotors
        self.motors = []
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String, lastUpdated: Date, sacnIP: String, universe: UInt32, dmxBase: UInt32, numberOfMotors: UInt32) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, lastUpdated: lastUpdated, sacnIP: sacnIP, universe: universe, dmxBase: dmxBase, numberOfMotors: numberOfMotors)
    }
    
    // Creates a new instance from a ProtoBuf object
    convenience init(serverCreature: Server_Creature) {
        self.init(id: serverCreature.id,
                  name: serverCreature.name,
                  lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                  sacnIP: serverCreature.sacnIp,
                  universe: serverCreature.universe,
                  dmxBase: serverCreature.dmxBase,
                  numberOfMotors: serverCreature.numberOfMotors)
        
        for motor in serverCreature.motors {
            addMotor(newMotor: motorFromServerCreatureMotor(motor: motor))
        }
        
        logger.debug("Created a new Creature from the Server_Creature convenience init-er")
    }
    
    // hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(lastUpdated)
        hasher.combine(sacnIP)
        hasher.combine(universe)
        hasher.combine(dmxBase)
        hasher.combine(numberOfMotors)
        hasher.combine(motors)
        hasher.combine(realData)
    }

    // The == operator
    static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.sacnIP == rhs.sacnIP &&
               lhs.universe == rhs.universe &&
               lhs.dmxBase == rhs.dmxBase &&
               lhs.numberOfMotors == rhs.numberOfMotors &&
               lhs.motors == rhs.motors &&
               lhs.realData == rhs.realData
    }
    
    func updateFromServerCreature(serverCreature: Server_Creature) {
        self.name = serverCreature.name
        self.sacnIP = serverCreature.sacnIp
        self.numberOfMotors = serverCreature.numberOfMotors
        self.dmxBase = serverCreature.dmxBase
        self.universe = serverCreature.universe
        self.lastUpdated = TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated)
        
        self.motors = []
        for motor in serverCreature.motors {
            addMotor(newMotor: motorFromServerCreatureMotor(motor: motor))
        }
    }
    
    func motorFromServerCreatureMotor(motor: Server_Creature.Motor) -> Motor {
        var newMotor = Motor(name: motor.name,
                             type: MotorType.servo,
                             number: motor.number,
                             maxValue: motor.maxValue,
                             minValue: motor.minValue,
                             smoothingValue: motor.smoothingValue)
        
        // If this is a stepper, make sure we update ourselves
        if motor.type == Server_Creature.MotorType.stepper {
            newMotor.type = .stepper
        }
        return newMotor
    }
    
    func addMotor(newMotor: Motor) -> Void {
        motors.append(newMotor)
    }
    
}





extension Creature {
    static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomData(byteCount: 12),
            name: "MockCreature",
            lastUpdated: Date(),
            sacnIP: "1.2.3.4",
            universe: 666,
            dmxBase: 7,
            numberOfMotors: 12)
        
        for i in 0..<12 {
            let motor = Motor(name: "Motor \(i+1) 🌈",
                              type: .servo,
                              number: UInt32(i),
                              maxValue: 1024,
                              minValue: 256,
                              smoothingValue: 0.95)
            creature.addMotor(newMotor: motor)
        }
        
        return creature
    }
}


extension CreatureIdentifier {
    static func mock() -> CreatureIdentifier {
        let creatureId = CreatureIdentifier(
            id: DataHelper.generateRandomData(byteCount: 12),
            name: "Mock Creature Id 🤖")
        
        return creatureId
    }
}
