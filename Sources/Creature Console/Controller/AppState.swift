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

    private var continuations: [UUID: AsyncStream<AppStateData>.Continuation] = [:]

    var stateUpdates: AsyncStream<AppStateData> {
        AsyncStream { continuation in
            let id = UUID()
            // Register this continuation and seed it with the current snapshot on the actor
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            // Clean up when the subscriber finishes
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
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

    private func addContinuation(id: UUID, _ continuation: AsyncStream<AppStateData>.Continuation) {
        self.continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(self.currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        self.continuations[id] = nil
    }

    private func publishState() {
        self.logger.debug("AppState: Broadcasting state (activity: \(self.currentActivity.description), showAlert: \(self.showSystemAlert))")
        let state = self.currentSnapshot()
        for continuation in self.continuations.values {
            continuation.yield(state)
        }
    }

    func setCurrentActivity(_ activity: Activity) {
        self.logger.info("AppState: Setting activity to \(activity.description)")
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
    var getCurrentActivity: Activity { self.currentActivity }
    var getCurrentAnimation: Common.Animation? { self.currentAnimation }
    var getSelectedTrack: CreatureIdentifier? { self.selectedTrack }
    var getShowSystemAlert: Bool { self.showSystemAlert }
    var getSystemAlertMessage: String { self.systemAlertMessage }
}
