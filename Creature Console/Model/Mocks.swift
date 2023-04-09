//
//  Mocks.swift
//  Creature Console
//
//  Created by April White on 4/8/23.
//

import Foundation


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

extension CreatureList {
    static func mock() -> CreatureList {
        let creaureList = CreatureList()
        
        let id1 = Creature.mock()
        id1.name = "Creature 1 🦜"
        id1.id = DataHelper.generateRandomData(byteCount: 12)
        
        let id2 = Creature.mock()
        id2.name = "Creature 2 🦖"
        id2.id = DataHelper.generateRandomData(byteCount: 12)
        
        let id3 = Creature.mock()
        id3.name = "Creature 3 🐰"
        id3.id = DataHelper.generateRandomData(byteCount: 12)
    
        creaureList.add(item: id1)
        creaureList.add(item: id2)
        creaureList.add(item: id3)
        
        return creaureList
    }
}
