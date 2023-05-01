//
//  CeratureTypes.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import Foundation
import GRPC
import SwiftUI
import SwiftProtobuf


/**
 This is a wrapper around the CreatureType from the protobufs, to allow for more control. It also allows me to implement other protocols.
 */


enum CreatureType: CaseIterable, CustomStringConvertible, Identifiable {
    
    case parrot
    case wledLight
    case other

    init?(protobufValue: Server_CreatureType) {
        switch protobufValue {
        case .parrot:
            self = .parrot
        case .wledLight:
            self = .wledLight
        case .other:
            self = .other
        default:
            return nil
        }
    }

    var systemImage: String {
        switch self {
        case .parrot:
            return "bird"
        case .wledLight:
            return "flame"
        default:
            return "folder.badge.questionmark"
        }
    }
    
    var description: String {
        switch self {
        case .parrot:
            return "Parrot"
        case .wledLight:
            return "WLED Light"
        case .other:
            return "Other"
        }
    }
    
    var id: String {
        switch self {
        case .parrot:
            return "Parrot"
        case .wledLight:
            return "WLED Light"
        case .other:
            return "Other"
        }
    }
    
    var protobufValue: Server_CreatureType {
        switch self {
        case .parrot:
            return .parrot
        case .wledLight:
            return .wledLight
        case .other:
            return .other
        }
    }
}
