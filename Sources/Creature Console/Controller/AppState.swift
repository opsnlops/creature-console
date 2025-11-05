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
    case countingDownForFilming

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
        case .countingDownForFilming:
            return "Countdown for Filming"
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

    private var continuations: [UUID: AsyncStream<AppStateData>.Continuation] = [:]

    var stateUpdates: AsyncStream<AppStateData> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            let currentState = self.currentSnapshot()
            self.logger.debug(
                "AppState: New subscriber \(id) - seeding with activity: \(currentState.currentActivity.description)"
            )

            // Send current state immediately to new subscriber
            continuation.yield(currentState)

            continuation.onTermination = { @Sendable _ in
                Task { [id] in
                    await self.removeContinuation(id)
                }
            }
        }
    }

    private init() {
        logger.info("AppState created")
    }

    private func currentSnapshot() -> AppStateData {
        AppStateData(
            currentActivity: self.currentActivity,
            currentAnimation: self.currentAnimation,
            selectedTrack: self.selectedTrack,
            showSystemAlert: self.showSystemAlert,
            systemAlertMessage: self.systemAlertMessage
        )
    }

    private func removeContinuation(_ id: UUID) {
        self.logger.debug("AppState: Removing subscriber \(id)")
        continuations.removeValue(forKey: id)
    }

    func getCurrentState() -> AppStateData {
        return currentSnapshot()
    }

    private func publishState() {
        let state = self.currentSnapshot()
        self.logger.debug(
            "AppState: Broadcasting state (activity: \(state.currentActivity.description), showAlert: \(state.showSystemAlert)) to \(self.continuations.count) subscribers"
        )
        for continuation in self.continuations.values {
            continuation.yield(state)
        }
    }

    func setCurrentActivity(_ activity: Activity) {
        self.logger.info(
            "AppState: Setting activity to \(activity.description) (from: \(Thread.callStackSymbols.first ?? "unknown"))"
        )
        self.currentActivity = activity
        self.publishState()
        self.logger.info("AppState: Published state with activity \(activity.description)")
    }

    func setCurrentAnimation(_ animation: Common.Animation?) {
        self.currentAnimation = animation
        self.publishState()
    }

    func setSelectedTrack(_ track: CreatureIdentifier?) {
        self.selectedTrack = track
        self.publishState()
    }

    func setSystemAlert(show: Bool, message: String = "") {
        self.showSystemAlert = show
        self.systemAlertMessage = message
        self.publishState()
    }

    // Getters for actor access
    var getCurrentActivity: Activity {
        self.logger.debug(
            "AppState: getCurrentActivity called - returning \(self.currentActivity.description)")
        return self.currentActivity
    }
    var getCurrentAnimation: Common.Animation? { self.currentAnimation }
    var getSelectedTrack: CreatureIdentifier? { self.selectedTrack }
    var getShowSystemAlert: Bool { self.showSystemAlert }
    var getSystemAlertMessage: String { self.systemAlertMessage }
}
