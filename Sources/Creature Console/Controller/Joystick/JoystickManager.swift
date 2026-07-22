import Common
import Foundation
import GameController
import OSLog

enum SelectedJoystick: Sendable, Equatable {
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

/// A singleton that reflects the current state of the joystick.
///
/// The hardware joysticks themselves are `@MainActor` (IOKit and GameController both deliver
/// on the main run loop); this actor mirrors their state once per event-loop tick via a single
/// main-actor hop and fans it out to subscribers off the main thread.
actor JoystickManager {
    static let shared = JoystickManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "JoystickManager")

    /// Current state of all joystick inputs, mirrored from the active joystick each poll
    var aButtonPressed = false
    var bButtonPressed = false
    var xButtonPressed = false
    var yButtonPressed = false
    var values: [UInt8] = Array(repeating: 0, count: 8)

    var connected: Bool = false
    var serialNumber: String?
    var versionNumber: Int?
    var manufacturer: String?
    private var selectedJoystick: SelectedJoystick = .sixAxis

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


    // Behold, the two genders. Immutable references to @MainActor objects, so both the actor
    // and main-actor sides of this type can reach them.
    let sixAxisJoystick: SixAxisJoystick
    #if os(macOS)
        let acwJoystick: AprilsCreatureWorkshopJoystick
    #endif


    private init() {
        self.sixAxisJoystick = SixAxisJoystick()
        #if os(macOS)
            self.acwJoystick = AprilsCreatureWorkshopJoystick(vendorID: 0x2e8a, productID: 0x1003)
        #endif

        // Subscribe to AppState changes to update joystick light automatically
        Task {
            logger.debug("Starting AppState subscription for joystick light updates")

            // Set initial light based on current AppState
            await self.updateJoystickLightFromCurrentAppState()

            for await appState in await AppState.shared.stateUpdates {
                await self.updateJoystickLight(activity: appState.currentActivity)
            }
            logger.warning("JoystickManager: AppState AsyncStream ended unexpectedly")
        }
    }

    /// Everything `poll()` needs from the active joystick, read in one main-actor hop.
    private struct JoystickSnapshot: Sendable {
        let selected: SelectedJoystick
        let connected: Bool
        let values: [UInt8]
        let aButtonPressed: Bool
        let bButtonPressed: Bool
        let xButtonPressed: Bool
        let yButtonPressed: Bool
        let serialNumber: String?
        let versionNumber: Int?
        let manufacturer: String?
    }

    /// Return whatever joystick we should use for an operation.
    ///
    /// On macOS this could be our own hardware or the system one; on iOS/tvOS IOKit doesn't
    /// exist, so it's always the system joystick.
    @MainActor
    private var activeJoystick: (joystick: Joystick, selected: SelectedJoystick) {
        #if os(macOS)
            if acwJoystick.connected
                && UserDefaults.standard.bool(forKey: "useOurJoystick")
            {
                return (acwJoystick, .acw)
            }
        #endif
        return (sixAxisJoystick, .sixAxis)
    }

    @MainActor
    private func pollActiveJoystick() -> JoystickSnapshot {
        let (joystick, selected) = activeJoystick

        if joystick.isConnected() {
            joystick.poll()
        }

        return JoystickSnapshot(
            selected: selected,
            connected: joystick.isConnected(),
            values: joystick.getValues(),
            aButtonPressed: joystick.aButtonPressed,
            bButtonPressed: joystick.bButtonPressed,
            xButtonPressed: joystick.xButtonPressed,
            yButtonPressed: joystick.yButtonPressed,
            serialNumber: joystick.serialNumber,
            versionNumber: joystick.versionNumber,
            manufacturer: joystick.manufacturer
        )
    }

    /// Called from the EventLoop when it's time for us to poll the joystick and mirror any
    /// changed values. Only publishes when something actually changed, which limits UI updates
    /// to the event-loop rate.
    func poll() async {
        let snapshot = await pollActiveJoystick()

        var stateChanged = false

        if snapshot.selected != self.selectedJoystick {
            self.selectedJoystick = snapshot.selected
            stateChanged = true
        }

        if snapshot.aButtonPressed != self.aButtonPressed {
            self.aButtonPressed = snapshot.aButtonPressed
            stateChanged = true
        }

        if snapshot.bButtonPressed != self.bButtonPressed {
            self.bButtonPressed = snapshot.bButtonPressed
            stateChanged = true
        }

        if snapshot.xButtonPressed != self.xButtonPressed {
            self.xButtonPressed = snapshot.xButtonPressed
            stateChanged = true
        }

        if snapshot.yButtonPressed != self.yButtonPressed {
            self.yButtonPressed = snapshot.yButtonPressed
            stateChanged = true
        }

        if snapshot.values != self.values {
            self.values = snapshot.values
            stateChanged = true
        }

        if stateChanged {
            publishState()
        }

        self.connected = snapshot.connected
        self.serialNumber = snapshot.serialNumber
        self.versionNumber = snapshot.versionNumber
        self.manufacturer = snapshot.manufacturer
    }

    func getValues() -> [UInt8] {
        return values
    }

    var isConnected: Bool { connected }
    var getManufacturer: String? { manufacturer }
    var getSerialNumber: String? { serialNumber }
    var getVersionNumber: Int? { versionNumber }

    private func currentSnapshot() -> JoystickManagerState {
        JoystickManagerState(
            aButtonPressed: aButtonPressed,
            bButtonPressed: bButtonPressed,
            xButtonPressed: xButtonPressed,
            yButtonPressed: yButtonPressed,
            selectedJoystick: selectedJoystick
        )
    }

    private func addContinuation(
        id: UUID, _ continuation: AsyncStream<JoystickManagerState>.Continuation
    ) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    @MainActor
    func updateJoystickLight(activity: Activity) {
        activeJoystick.joystick.updateJoystickLight(activity: activity)
    }

    func updateJoystickLightFromCurrentAppState() async {
        let currentActivity = await AppState.shared.getCurrentActivity
        await updateJoystickLight(activity: currentActivity)
    }

    @MainActor
    func getBButtonSymbol() -> String {
        activeJoystick.joystick.getBButtonSymbol()
    }

    @MainActor
    func getAButtonSymbol() -> String {
        activeJoystick.joystick.getAButtonSymbol()
    }

    @MainActor
    func getXButtonSymbol() -> String {
        activeJoystick.joystick.getXButtonSymbol()
    }

    @MainActor
    func getYButtonSymbol() -> String {
        activeJoystick.joystick.getYButtonSymbol()
    }

    /// Re-scan the connected GameController devices and adopt the first extended gamepad.
    /// Called on connect/disconnect notifications; scanning here (instead of passing the
    /// controller in) keeps the non-Sendable `GCController` from ever crossing isolation.
    @MainActor
    func refreshSixAxisController() {
        let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        sixAxisJoystick.controller = controller

        // Update light when controller connects based on current AppState
        if controller != nil {
            Task {
                await self.updateJoystickLightFromCurrentAppState()
            }
        }
    }

    @MainActor
    func configureACWJoystick() {
        #if os(macOS)
            acwJoystick.setMatchingCriteria()
            acwJoystick.registerCallbacks()
            acwJoystick.openManager()
            acwJoystick.scheduleWithRunLoop()
        #endif
    }

    func playRecordingCountdownHaptics() async {
        await sixAxisJoystick.playRecordingCountdownHaptics()
    }

    func cancelRecordingCountdownHaptics() async {
        await sixAxisJoystick.cancelRecordingCountdownHaptics()
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
