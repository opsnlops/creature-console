//
//  Creature.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import OSLog



/**
 This is a localized view of a Creature
 
 We need this wrapper so we can make the object observable
 */
class Creature : ObservableObject, Identifiable, Hashable, Equatable {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "Creature")
    var id : Data
    @Published var name : String
    @Published var lastUpdated : Date
    @Published var sacnIP : String
    @Published var universe : UInt32
    @Published var dmxBase : UInt32
    @Published var numberOfMotors : UInt32
    @Published var type : CreatureType
    @Published var motors : [Motor]
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded

    init(id: Data, name: String, type: CreatureType, lastUpdated: Date, sacnIP: String, universe: UInt32, dmxBase: UInt32, numberOfMotors: UInt32) {
        self.id = id
        self.name = name
        self.type = type
        self.lastUpdated = lastUpdated
        self.sacnIP = sacnIP
        self.universe = universe
        self.dmxBase = dmxBase
        self.numberOfMotors = numberOfMotors
        self.motors = []
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String, type: CreatureType, lastUpdated: Date, sacnIP: String, universe: UInt32, dmxBase: UInt32, numberOfMotors: UInt32) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, type: type, lastUpdated: lastUpdated, sacnIP: sacnIP, universe: universe, dmxBase: dmxBase, numberOfMotors: numberOfMotors)
    }
    
    // Creates a new instance from a ProtoBuf object
    convenience init(serverCreature: Server_Creature) {
        
        guard let creatureType = CreatureType(protobufValue: serverCreature.type) else {
            // Handle the case where the creature type could not be created. 😬🙅‍♀️🚫🔥
            print("Invalid creature type! Assuming a WLED Light!") // 🚨🔔⚠️💔
            
            self.init(id: serverCreature.id,
                      name: serverCreature.name,
                      type: .wledLight,
                      lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                      sacnIP: serverCreature.sacnIp,
                      universe: serverCreature.universe,
                      dmxBase: serverCreature.dmxBase,
                      numberOfMotors: serverCreature.numberOfMotors)
            return
            
        }
        
        self.init(id: serverCreature.id,
                  name: serverCreature.name,
                  type: creatureType,
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
            type: .parrot,
            lastUpdated: Date(),
            sacnIP: "192.168.1.1",
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


