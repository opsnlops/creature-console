import Common
import Foundation
import SwiftUI

/// A singleton that reflects the current state of the joystick
class JoystickManager: ObservableObject {
    static let shared = JoystickManager()

    @AppStorage("useOurJoystick") var useOurJoystick: Bool = false

    /// Publish the current state of all of our things
    @Published var aButtonPressed = false
    @Published var bButtonPressed = false
    @Published var xButtonPressed = false
    @Published var yButtonPressed = false
    @Published var values: [UInt8] = Array(repeating: 0, count: 8)

    @Published var connected: Bool = false
    @Published var serialNumber: String?
    @Published var versionNumber: Int?
    @Published var manufacturer: String?


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
    }

    /// Called from the EventManager when it's time for us to poll the joystick and update any changed values
    func poll() {

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
            if joystick.aButtonPressed != self.aButtonPressed {
                DispatchQueue.main.async {
                    self.aButtonPressed = joystick.aButtonPressed
                }
            }

            if joystick.bButtonPressed != self.bButtonPressed {
                DispatchQueue.main.async {
                    self.bButtonPressed = joystick.bButtonPressed
                }
            }

            if joystick.xButtonPressed != self.xButtonPressed {
                DispatchQueue.main.async {
                    self.xButtonPressed = joystick.xButtonPressed
                }
            }

            if joystick.yButtonPressed != self.yButtonPressed {
                DispatchQueue.main.async {
                    self.yButtonPressed = joystick.yButtonPressed
                }
            }

            if joystick.getValues() != self.values {
                DispatchQueue.main.async {
                    self.values = joystick.getValues()
                }
            }

            if joystick.isConnected() != self.connected {
                DispatchQueue.main.async {
                    self.connected = joystick.isConnected()
                }
            }

            if joystick.serialNumber != self.serialNumber {
                DispatchQueue.main.async {
                    self.serialNumber = joystick.serialNumber
                }
            }

            if joystick.versionNumber != self.versionNumber {
                DispatchQueue.main.async {
                    self.versionNumber = joystick.versionNumber
                }
            }

            if joystick.manufacturer != self.manufacturer {
                DispatchQueue.main.async {
                    self.manufacturer = joystick.manufacturer
                }
            }

        }
    }


    /**
     Return whatever the joystick is we should use for an operation
     */
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
        #if os(iOS)
            joystick = sixAxisJoystick
        #endif

        return joystick
    }


}


extension JoystickManager {
    static func mock() -> JoystickManager {
        let mockJoystickManager = JoystickManager()

        // Configure the mock joystick if needed
        mockJoystickManager.sixAxisJoystick = .mock()
        #if os(macOS)
            mockJoystickManager.acwJoystick = .mock()
        #endif


        return mockJoystickManager
    }
}
