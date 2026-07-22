import Common
import Foundation

/// The hardware joysticks live on the main actor: IOKit delivers ACW input on the main run
/// loop, GameController posts its connect/disconnect notifications on the main queue, and
/// controller lights and haptics are main-thread-affine. Isolating the protocol here makes
/// that contract compiler-enforced instead of hoped-for.
@MainActor
protocol Joystick {

    /**
     Is the joystick currently connected?
     */
    func isConnected() -> Bool

    /**
    Get the current values of the axii. The size of the array should vary depending on the type of joystick being used
     */
    func getValues() -> [UInt8]

    /**
    Poll, if needed. Can be a no-op.
     */
    func poll()

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
