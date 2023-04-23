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
        var millisecondsPerFrame: Int32
        var numberOfFrames = 0
        var creatureType: Server_CreatureType
        var numberOfMotors: Int32
        var notes: String

        init(title: String, millisecondsPerFrame: Int32, creatureType: Server_CreatureType, numberOfMotors: Int32, notes: String) {
            self.title = title
            self.millisecondsPerFrame = millisecondsPerFrame
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
    
    /**
     Convert this into something we can send to the server
     
     Note that this is making a copy of it. That migiht not be what we actually want if the animation is huge, but all of my devices have a lot of memory, sooo....
     */
    func toServerAnimation() throws -> Server_Animation {
        
        var animation = Server_Animation()
        
        animation.id = self.id
        
        // Convert the metadata
        animation.metadata.title = self.metadata.title
        animation.metadata.creatureType = self.metadata.creatureType
        animation.metadata.millisecondsPerFrame = self.metadata.millisecondsPerFrame
        animation.metadata.numberOfFrames = self.numberOfFrames
        animation.metadata.numberOfMotors = self.metadata.numberOfMotors
        animation.metadata.notes = self.metadata.notes

        // Convert the frames
        for f in self.frames {
            var frame = Server_Animation.Frame()
            let motorBytesData = Data(f.motorBytes) // Convert [UInt8] to Data
            frame.bytes.append(motorBytesData)
            animation.frames.append(frame) // Add the frame to the animation
        }
        
        return animation
        
    }
}
