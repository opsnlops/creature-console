//
//  Animation.swift
//  Creature Console
//
//  Created by April White on 4/20/23.
//

import Foundation

class Animation {
    
    var id: Data
    var metadata: Metadata
    var frames: [Frame]

    init(id: Data, metadata: Metadata, frames: [Frame]) {
        self.id = id
        self.metadata = metadata
        self.frames = frames
    }
    
    init(fromServerAnimation: Server_Animation) {
        self.id = fromServerAnimation.id
        self.metadata = Metadata(serverAnimationMetadata: fromServerAnimation.metadata)
        self.frames = []
        
        for frame in fromServerAnimation.frames {
            let animationFrame = Frame(motorBytes: frame.bytes.flatMap { [UInt8]($0) })
            frames.append(animationFrame)
        }
    }
    
    
    class Metadata {
        var title: String
        var millisecondsPerFrame: Int32
        var numberOfFrames = Int32(0)
        var creatureType: Server_CreatureType
        var numberOfMotors: Int32
        var notes: String
        var animationId: Data
        var soundFile: String

        init(animationId: Data, title: String, millisecondsPerFrame: Int32, creatureType: Server_CreatureType, numberOfMotors: Int32, notes: String, soundFile: String) {
            self.animationId = animationId
            self.title = title
            self.millisecondsPerFrame = millisecondsPerFrame
            self.creatureType = creatureType
            self.numberOfMotors = numberOfMotors
            self.notes = notes
            self.soundFile = soundFile
        }
        
        init(serverAnimationMetadata: Server_Animation.Metadata) {
            self.animationId = serverAnimationMetadata.animationID
            self.title = serverAnimationMetadata.title
            self.millisecondsPerFrame = serverAnimationMetadata.millisecondsPerFrame
            self.creatureType = serverAnimationMetadata.creatureType
            self.numberOfFrames = serverAnimationMetadata.numberOfFrames
            self.numberOfMotors = serverAnimationMetadata.numberOfMotors
            self.notes = serverAnimationMetadata.notes
            self.soundFile = serverAnimationMetadata.soundFile
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
    
    /**
     Convert this into something we can send to the server
     
     Note that this is making a copy of it. That might not be what we actually want if the animation is huge, but all of my devices have a lot of memory, sooo....
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
        animation.metadata.soundFile = self.metadata.soundFile

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


extension Animation {
    static func mock() -> Animation {
        let metadata = Metadata(
            animationId: DataHelper.generateRandomData(byteCount: 12),
            title: "Mock Animation",
            millisecondsPerFrame: 50,
            creatureType: .parrot,
            numberOfMotors: 6,
            notes: "Sample animation for testing purposes",
            soundFile: "soundsOfBirds.flac"
        )

        // Create sample frames with random motor bytes
        let numberOfSampleFrames = 40
        let numberOfMotors = Int(metadata.numberOfMotors)
        var frames = [Frame]()
        for _ in 0..<numberOfSampleFrames {
            let motorBytes = (0..<numberOfMotors).map { _ in UInt8.random(in: 0...255) }
            frames.append(Frame(motorBytes: motorBytes))
        }

        let id = DataHelper.generateRandomData(byteCount: 24)
        let animation = Animation(id: id, metadata: metadata, frames: frames)

        return animation
    }
}

extension Animation.Metadata {
    static func mock() -> Animation.Metadata {
        let title = "Mock Metadata"
        let millisecondsPerFrame: Int32 = 23
        let creatureType: Server_CreatureType = .parrot
        let numberOfMotors: Int32 = 6
        let notes = "Sample metadata for testing purposes"
        let animationId = DataHelper.generateRandomData(byteCount: 12)
        let soundFile = "mockSoundfile.mp3"

        let metadata = Animation.Metadata(
            animationId: animationId,
            title: title,
            millisecondsPerFrame: millisecondsPerFrame,
            creatureType: creatureType,
            numberOfMotors: numberOfMotors,
            notes: notes,
            soundFile: soundFile
        )

        return metadata
    }
}
