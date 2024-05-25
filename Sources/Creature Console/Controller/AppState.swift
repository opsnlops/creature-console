import Combine
import Common
import Foundation
import OSLog

class AppState: ObservableObject {

    // Use the singleton pattern to make sure only one of these exists in a way
    // that can be used in non SwiftUI code
    static let shared = AppState()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AppState")

    @Published var currentActivity = Activity.idle

    @Published var currentAnimation: Common.Animation?
    @Published var selectedTrack: CreatureIdentifier?

    // The bottom toolbar watches these to know when to show an alert message, which
    // normally comes in off the websocket from the server
    @Published var showSystemAlert: Bool = false
    @Published var systemAlertMessage: String = ""

    private var cancellables = Set<AnyCancellable>()

    // Make our constructor private so we don't accidentally
    // create more than one of these
    private init() {
        logger.info("AppState created")

        // Observe changes to the currentAnimation so we can inform others
        $currentAnimation
            .compactMap { $0 }
            .flatMap { animation in
                animation.objectWillChange
            }
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

    }

    enum Activity: CustomStringConvertible {
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
