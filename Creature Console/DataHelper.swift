//
//  DataHelper.swift
//  Creature Console
//
//  Created by April White on 4/7/23.
//

import Foundation


struct DataHelper {
    
    /**
     Generates random bytes
     
     Can be used to generate MongoDB style OIDs.
     */
    static func generateRandomData(byteCount: Int) -> Data {
        return Data((0..<byteCount).map { _ in UInt8.random(in: 0...UInt8.max) })
    }
    
}
