import Common
import Foundation
import GameController
import OSLog
import SwiftUI

enum SelectedJoystick: Sendable {
    case sixAxis
    case acw
    case none

    func getBButtonSymbol() -> String {
        switch self {
        case .sixAxis:
            return "b.circle"
        case .acw:
            return "b.square"
        case .none:
            return "questionmark.circle"
        }
    }
}

struct JoystickManagerState: Sendable {
    let aButtonPressed: Bool
    let bButtonPressed: Bool
    let xButtonPressed: Bool
    let yButtonPressed: Bool
    let selectedJoystick: SelectedJoystick
}

/// A singleton that reflects the current state of the joystick
actor JoystickManager {
    static let shared = JoystickManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "JoystickManager")

    @AppStorage("useOurJoystick") var useOurJoystick: Bool = false

    /// Current state of all joystick inputs
    var aButtonPressed = false
    var bButtonPressed = false
    var xButtonPressed = false
    var yButtonPressed = false
    var values: [UInt8] = Array(repeating: 0, count: 8)

    var connected: Bool = false
    var serialNumber: String?
    var versionNumber: Int?
    var manufacturer: String?

    private var continuations: [UUID: AsyncStream<JoystickManagerState>.Continuation] = [:]

    var stateUpdates: AsyncStream<JoystickManagerState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }


    // Behold, the two genders
    var sixAxisJoystick: SixAxisJoystick
    #if os(macOS)
        var acwJoystick: AprilsCreatureWorkshopJoystick
    #endif


    private init() {
        self.sixAxisJoystick = SixAxisJoystick()
        #if os(macOS)
            self.acwJoystick = AprilsCreatureWorkshopJoystick(vendorID: 0x0666, productID: 0x0001)
        #endif

        // Subscribe to AppState changes to update joystick light automatically
        Task {
            logger.debug("Starting AppState subscription for joystick light updates")

            // Set initial light based on current AppState
            await self.updateJoystickLightFromCurrentAppState()

            for await appState in await AppState.shared.stateUpdates {
                logger.info(
                    "JoystickManager: Received AppState update, activity: \(appState.currentActivity.description)"
                )
                await self.updateJoystickLight(activity: appState.currentActivity)
            }
            logger.warning("JoystickManager: AppState AsyncStream ended unexpectedly")
        }
    }

    private var lastKnownActivity: Activity = .idle

    /// Called from the EventManager when it's time for us to poll the joystick and update any changed values
    func poll() {

        // Check if AppState has changed and update joystick light if needed
        Task {
            let currentActivity = await AppState.shared.getCurrentActivity
            if currentActivity != self.lastKnownActivity {
                logger.info(
                    "JoystickManager: AppState changed from \(self.lastKnownActivity.description) to \(currentActivity.description) - updating light"
                )
                self.lastKnownActivity = currentActivity
                self.updateJoystickLight(activity: currentActivity)
            }
        }

        // Which joystick should we use for this pass?
        let joystick = getActiveJoystick()


        // If we have a joystick, poll it
        if joystick.isConnected() {

            // Tell the joystick to poll itself
            joystick.poll()


            //
            // Now look at each value and only update things if there's a change. This saves
            // sending a bunch of Published events when nothing actually changes. (It also limits
            // them to running at our EventLoop speed.)
            //
            var stateChanged = false

            if joystick.aButtonPressed != self.aButtonPressed {
                self.aButtonPressed = joystick.aButtonPressed
                stateChanged = true
            }

            if joystick.bButtonPressed != self.bButtonPressed {
                self.bButtonPressed = joystick.bButtonPressed
                stateChanged = true
            }

            if joystick.xButtonPressed != self.xButtonPressed {
                self.xButtonPressed = joystick.xButtonPressed
                stateChanged = true
            }

            if joystick.yButtonPressed != self.yButtonPressed {
                self.yButtonPressed = joystick.yButtonPressed
                stateChanged = true
            }

            if joystick.getValues() != self.values {
                self.values = joystick.getValues()
                stateChanged = true
            }

            if stateChanged {
                publishState()
            }

            if joystick.isConnected() != self.connected {
                self.connected = joystick.isConnected()
            }

            if joystick.serialNumber != self.serialNumber {
                self.serialNumber = joystick.serialNumber
            }

            if joystick.versionNumber != self.versionNumber {
                self.versionNumber = joystick.versionNumber
            }

            if joystick.manufacturer != self.manufacturer {
                self.manufacturer = joystick.manufacturer
            }

        }
    }


    /// Return whatever the joystick is we should use for an operation
    func getActiveJoystick() -> Joystick {

        var joystick: Joystick

        /**
         On macOS we could our joystick, or the system one.
         */
        #if os(macOS)
            if acwJoystick.connected && useOurJoystick {
                joystick = acwJoystick
            } else {
                joystick = sixAxisJoystick
            }
        #endif

        /**
         On iOS we don't have a choice. IOKit does not exist there.
         */
        #if os(iOS) || os(tvOS)
            joystick = sixAxisJoystick
        #endif

        return joystick
    }

    func getValues() -> [UInt8] {
        return values
    }

    var isConnected: Bool { connected }
    var getManufacturer: String? { manufacturer }
    var getSerialNumber: String? { serialNumber }
    var getVersionNumber: Int? { versionNumber }

    private func currentSnapshot() -> JoystickManagerState {
        let selectedJoystick: SelectedJoystick
        #if os(macOS)
            if acwJoystick.connected && useOurJoystick {
                selectedJoystick = .acw
            } else {
                selectedJoystick = .sixAxis
            }
        #else
            selectedJoystick = .sixAxis
        #endif
        return JoystickManagerState(
            aButtonPressed: aButtonPressed,
            bButtonPressed: bButtonPressed,
            xButtonPressed: xButtonPressed,
            yButtonPressed: yButtonPressed,
            selectedJoystick: selectedJoystick
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<JoystickManagerState>.Continuation) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        logger.debug("JoystickManager: Broadcasting state (A: \(self.aButtonPressed), B: \(self.bButtonPressed), X: \(self.xButtonPressed), Y: \(self.yButtonPressed), selected: \(String(describing: snapshot.selectedJoystick)))")
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func updateJoystickLight(activity: Activity) {
        logger.info(
            "JoystickManager: Updating joystick light for activity: \(activity.description)")
        let joystick = getActiveJoystick()
        joystick.updateJoystickLight(activity: activity)
    }

    func updateJoystickLightFromCurrentAppState() async {
        let currentActivity = await AppState.shared.getCurrentActivity
        logger.info(
            "JoystickManager: Updating joystick light from current AppState: \(currentActivity.description)"
        )
        let joystick = getActiveJoystick()
        joystick.updateJoystickLight(activity: currentActivity)
    }

    func getBButtonSymbol() -> String {
        let joystick = getActiveJoystick()
        return joystick.getBButtonSymbol()
    }

    func getAButtonSymbol() -> String {
        let joystick = getActiveJoystick()
        return joystick.getAButtonSymbol()
    }

    func getXButtonSymbol() -> String {
        let joystick = getActiveJoystick()
        return joystick.getXButtonSymbol()
    }

    func getYButtonSymbol() -> String {
        let joystick = getActiveJoystick()
        return joystick.getYButtonSymbol()
    }

    func setSixAxisController(_ controller: SendableGCController?) {
        sixAxisJoystick.controller = controller?.controller

        // Update light when controller connects based on current AppState
        if controller != nil {
            Task {
                await self.updateJoystickLightFromCurrentAppState()
            }
        }
    }

    func configureACWJoystick() {
        #if os(macOS)
            acwJoystick.setMatchingCriteria()
            acwJoystick.registerCallbacks()
            acwJoystick.openManager()
            acwJoystick.scheduleWithRunLoop()
        #endif
    }
}


extension JoystickManager {
    static func mock() -> JoystickManager {
        let mockJoystickManager = JoystickManager()
        // Note: Mock joystick configuration removed for Swift 6 actor compliance
        // If needed, configure joysticks through actor methods after creation
        return mockJoystickManager
    }
}
