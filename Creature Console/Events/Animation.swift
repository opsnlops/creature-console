//
//  Animation.swift
//  Creature Console
//
//  Created by April White on 4/20/23.
//

import Foundation

class Animation {
    class Metadata {
        var title: String
        var framesPerSecond: Int32
        var numberOfFrames = 0
        var creatureType: Server_CreatureType
        var numberOfMotors: Int32
        var notes: String

        init(title: String, framesPerSecond: Int32, creatureType: Server_CreatureType, numberOfMotors: Int32, notes: String) {
            self.title = title
            self.framesPerSecond = framesPerSecond
            self.creatureType = creatureType
            self.numberOfMotors = numberOfMotors
            self.notes = notes
        }
    }
    
    var numberOfFrames : Int32 {
        return Int32(frames.count)
    }
    
    // Helper function to append data quickly
    func addFrame(frames: [UInt8]) {
        self.frames.append(Frame(motorBytes: frames))
    }
    
    class Frame {
        var motorBytes: [UInt8]

        init(motorBytes: [UInt8]) {
            self.motorBytes = motorBytes
        }
    }
    
    var id: Data
    var metadata: Metadata
    var frames: [Frame]

    init(id: Data, metadata: Metadata, frames: [Frame]) {
        self.id = id
        self.metadata = metadata
        self.frames = frames
    }
}
