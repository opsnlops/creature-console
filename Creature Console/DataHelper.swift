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
    
    static func dataToHexString(data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
    
    static func stringToOidData(oid: String) -> Data? {
        var data = Data(capacity: oid.count / 2)
        var index = oid.startIndex
        while index < oid.endIndex {
            let nextIndex = oid.index(index, offsetBy: 2)
            if let b = UInt8(oid[index..<nextIndex], radix: 16) {
                data.append(b)
            } else {
                return nil // Return nil if the conversion fails
            }
            index = nextIndex
        }
        return data
    }
}
