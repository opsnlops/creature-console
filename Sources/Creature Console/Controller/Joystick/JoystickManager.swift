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
    let values: [UInt8]
    let connected: Bool
    let manufacturer: String?
    let serialNumber: String?
    let versionNumber: Int?

    /// A resting, disconnected state — the value to seed UI with before the first update.
    static let initial = JoystickManagerState(
        aButtonPressed: false,
        bButtonPressed: false,
        xButtonPressed: false,
        yButtonPressed: false,
        selectedJoystick: .sixAxis,
        values: [],
        connected: false,
        manufacturer: nil,
        serialNumber: nil,
        versionNumber: nil
    )
}

/// A singleton that reflects the current state of the joystick.
///
/// The hardware joysticks themselves are `@MainActor` (IOKit and GameController both deliver
/// on the main run loop), but input is event-driven: the OS pushes changes into each
/// joystick's lock-protected `mirror`, and this actor samples the mirror once per event-loop
/// tick — no main-actor hop, so the control cadence can't be starved by UI work (issue #56) —
/// and fans changes out to subscribers off the main thread.
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

    /// Sample the active joystick's state mirror. The OS pushes hardware events into the
    /// mirrors as they happen (IOKit callbacks, GameController value-changed handlers), so
    /// this is a lock-protected read — **no main-actor hop** — and the event loop's cadence
    /// stays independent of main-thread health (issue #56). `UserDefaults` is thread-safe.
    private func sampleActiveJoystick() -> (state: JoystickState, selected: SelectedJoystick) {
        #if os(macOS)
            let acwState = acwJoystick.mirror.current
            if acwState.connected && UserDefaults.standard.bool(forKey: "useOurJoystick") {
                return (acwState, .acw)
            }
        #endif
        return (sixAxisJoystick.mirror.current, .sixAxis)
    }

    /// Called from the EventLoop when it's time to sample the joystick and mirror any
    /// changed values. Only publishes when something actually changed, which limits UI updates
    /// to the event-loop rate.
    func poll() {
        let (snapshot, selected) = sampleActiveJoystick()

        var stateChanged = false

        if selected != self.selectedJoystick {
            self.selectedJoystick = selected
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

        // Connection state and device metadata are part of the published state too — a
        // subscriber (like the debug view) needs to see connects and disconnects.
        if snapshot.connected != self.connected {
            self.connected = snapshot.connected
            stateChanged = true
        }

        if snapshot.serialNumber != self.serialNumber
            || snapshot.versionNumber != self.versionNumber
            || snapshot.manufacturer != self.manufacturer
        {
            self.serialNumber = snapshot.serialNumber
            self.versionNumber = snapshot.versionNumber
            self.manufacturer = snapshot.manufacturer
            stateChanged = true
        }

        if stateChanged {
            publishState()
        }
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
            selectedJoystick: selectedJoystick,
            values: values,
            connected: connected,
            manufacturer: manufacturer,
            serialNumber: serialNumber,
            versionNumber: versionNumber
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
