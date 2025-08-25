import Combine
import Common
import Foundation

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
     Since this is a protocol, we can't be observed directly. Require implementors to be able to signal when their values change.
     */
    var changesPublisher: AnyPublisher<Void, Never> { get }

    /**
     Update joystick light based on activity state
     */
    func updateJoystickLight(activity: Activity)
}
