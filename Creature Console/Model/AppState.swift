//
//  AppState.swift
//  Creature Console
//
//  Created by April White on 5/28/23.
//

import Foundation


class AppState : ObservableObject {
    
    @Published var currentActivity = Activity.idle
    @Published var activeCreature : Creature?
    
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
        appState.activeCreature = .mock()
        return appState
    }
}
