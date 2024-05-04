
import Foundation
import OSLog


class AppState : ObservableObject {
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AppState")
    
    @Published var currentActivity = Activity.idle
    
    
    enum Activity : CustomStringConvertible {
        case idle
        case streaming
        case recording
        case preparingToRecord
        case playingAnimation
        case connectingToServer
        
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
            case .playingAnimation:
                return "Playing Animation"
            case .connectingToServer:
                return "Connecting to Server"
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
