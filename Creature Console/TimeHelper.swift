//
//  TimeHelper.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import Foundation
import SwiftProtobuf


struct TimeHelper {
    
    static func dateToTimestamp(date: Date) -> Google_Protobuf_Timestamp {
        let timeInterval = date.timeIntervalSince1970
        let seconds = Int64(timeInterval)
        let nanoseconds = Int32((timeInterval - Double(seconds)) * 1_000_000_000)

        var timestamp = Google_Protobuf_Timestamp()
        timestamp.seconds = seconds
        timestamp.nanos = nanoseconds

        return timestamp
    }
    
    static func timestampToDate(timestamp: Google_Protobuf_Timestamp) -> Date {
        let timeInterval = TimeInterval(timestamp.seconds) + TimeInterval(timestamp.nanos) / 1_000_000_000
        return Date(timeIntervalSince1970: timeInterval)
    }
    
}
