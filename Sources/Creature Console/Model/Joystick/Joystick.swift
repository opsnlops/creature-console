import Common
import Foundation
import Synchronization

struct JoystickState: Sendable {
    let connected: Bool
    let values: [UInt8]
    let aButtonPressed: Bool
    let bButtonPressed: Bool
    let xButtonPressed: Bool
    let yButtonPressed: Bool
    let serialNumber: String?
    let versionNumber: Int?
    let manufacturer: String?

    /// A disconnected joystick with `axisCount` axes at their resting values.
    static func initial(axisCount: Int, restingValue: UInt8 = 127) -> JoystickState {
        JoystickState(
            connected: false,
            values: Array(repeating: restingValue, count: axisCount),
            aButtonPressed: false,
            bButtonPressed: false,
            xButtonPressed: false,
            yButtonPressed: false,
            serialNumber: nil,
            versionNumber: nil,
            manufacturer: nil
        )
    }
}

/// Lock-protected snapshot of a joystick's hardware state.
///
/// The OS delivers joystick input as *events* (IOKit HID callbacks, GameController
/// value-changed handlers), and those handlers run on the main run loop. The event loop,
/// though, needs to *sample* the current state every 20ms — and awaiting a main-actor hop
/// for that sample makes the robot control cadence hostage to main-thread health (a color
/// wheel drag could starve it, issue #56). Each joystick publishes its state here whenever
/// the OS delivers an event, and the event loop reads it from any isolation in nanoseconds.
final class JoystickStateMirror: Sendable {
    private let state: Mutex<JoystickState>

    init(initial: JoystickState) {
        state = Mutex(initial)
    }

    var current: JoystickState {
        state.withLock { $0 }
    }

    func update(_ newState: JoystickState) {
        state.withLock { $0 = newState }
    }
}

/// The hardware joysticks live on the main actor: IOKit delivers ACW input on the main run
/// loop, GameController posts its connect/disconnect notifications on the main queue, and
/// controller lights and haptics are main-thread-affine. Isolating the protocol here makes
/// that contract compiler-enforced instead of hoped-for.
///
/// Input is event-driven: the OS pushes changes into each joystick's `mirror`, which the
/// event loop samples at its own cadence without touching the main actor.
@MainActor
protocol Joystick {

    /// Lock-protected snapshot of this joystick's state, written by the OS event handlers.
    /// Readable from any isolation — this is how the event loop samples input each frame.
    nonisolated var mirror: JoystickStateMirror { get }

    /**
     Is the joystick currently connected?
     */
    func isConnected() -> Bool

    /**
    Get the current values of the axii. The size of the array should vary depending on the type of joystick being used
     */
    func getValues() -> [UInt8]

    /**
    Who makes this joystick? Shown in the UI
     */
    var manufacturer: String { get }
    var serialNumber: String { get }
    var versionNumber: Int { get }

    /**
     Buttons!
     */
    var aButtonPressed: Bool { get }
    var bButtonPressed: Bool { get }
    var xButtonPressed: Bool { get }
    var yButtonPressed: Bool { get }

    /**
     What systemImage should we use for each button type?
     */
    func getAButtonSymbol() -> String
    func getBButtonSymbol() -> String
    func getXButtonSymbol() -> String
    func getYButtonSymbol() -> String

    /**
     Update joystick light based on activity state
     */
    func updateJoystickLight(activity: Activity)
}
