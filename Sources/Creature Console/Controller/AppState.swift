import Common
import Foundation
import OSLog

enum Activity: CustomStringConvertible, Sendable {
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

struct AppStateData: Sendable {
    let currentActivity: Activity
    let currentAnimation: Common.Animation?
    let selectedTrack: CreatureIdentifier?
    let showSystemAlert: Bool
    let systemAlertMessage: String
}

actor AppState {
    static let shared = AppState()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AppState")

    private var currentActivity = Activity.idle
    private var currentAnimation: Common.Animation?
    private var selectedTrack: CreatureIdentifier?
    private var showSystemAlert: Bool = false
    private var systemAlertMessage: String = ""

    // AsyncStream for UI updates
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(of: AppStateData.self)
    
    var stateUpdates: AsyncStream<AppStateData> {
        return stateStream
    }

    private init() {
        logger.info("AppState created")
        // Publish initial state synchronously
        let state = AppStateData(
            currentActivity: currentActivity,
            currentAnimation: currentAnimation,
            selectedTrack: selectedTrack,
            showSystemAlert: showSystemAlert,
            systemAlertMessage: systemAlertMessage
        )
        stateContinuation.yield(state)
    }

    private func publishState() {
        let state = AppStateData(
            currentActivity: currentActivity,
            currentAnimation: currentAnimation,
            selectedTrack: selectedTrack,
            showSystemAlert: showSystemAlert,
            systemAlertMessage: systemAlertMessage
        )
        stateContinuation.yield(state)
    }

    func setCurrentActivity(_ activity: Activity) {
        logger.info("AppState: Setting activity to \(activity.description)")
        currentActivity = activity
        publishState()
        logger.info("AppState: Published state with activity \(activity.description)")
    }

    func setCurrentAnimation(_ animation: Common.Animation?) {
        currentAnimation = animation
        publishState()
    }

    func setSelectedTrack(_ track: CreatureIdentifier?) {
        selectedTrack = track
        publishState()
    }

    func setSystemAlert(show: Bool, message: String = "") {
        showSystemAlert = show
        systemAlertMessage = message
        publishState()
    }

    // Getters for actor access
    var getCurrentActivity: Activity { currentActivity }
    var getCurrentAnimation: Common.Animation? { currentAnimation }
    var getSelectedTrack: CreatureIdentifier? { selectedTrack }
    var getShowSystemAlert: Bool { showSystemAlert }
    var getSystemAlertMessage: String { systemAlertMessage }
}


