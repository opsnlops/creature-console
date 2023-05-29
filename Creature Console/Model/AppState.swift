//
//  AppState.swift
//  Creature Console
//
//  Created by April White on 5/28/23.
//

import Foundation
import Logging


class AppState : ObservableObject {
    
    let logger = Logger(label: "AppState")
    
    @Published var currentActivity = Activity.idle
    
    
    enum Activity : CustomStringConvertible {
        case idle
        case streaming
        case recording
        case preparingToRecord
        
        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .streaming:
                return "Streaming"
            case .recording:
                return "Recording"
            case .preparingToRecord:
                return "Preparing to Record"
            }
        }
    }
    
}


extension AppState {
    static func mock() -> AppState {
        let appState = AppState()
        appState.currentActivity = .idle
        return appState
    }
}
