//
//  RhubarbData.swift
//  Creature Console
//
//  Created by April White on 8/22/23.
//

import Foundation


struct SoundData: Decodable {
    struct Metadata: Decodable {
        let soundFile: String
        let duration: Double
    }
    
    struct MouthCue: Codable {
            let start: Double
            let end: Double
            let value: String
            
            var intValue: UInt8 {
                switch value {
                case "A": return 5
                case "B": return 180
                case "C": return 240
                case "D": return 255
                case "E": return 50
                case "F": return 20
                case "X": return 0
                default: return 5 // Default value
                }
            }
        }

    let metadata: Metadata
    let mouthCues: [MouthCue]
}
