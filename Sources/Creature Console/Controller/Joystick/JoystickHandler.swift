import Common
import Foundation
import GameController
import OSLog

#if os(macOS)
    import IOKit
#endif

// Make GCController sendable for our concurrency needs - it's effectively thread-safe for our usage
extension GCController: @unchecked Sendable {}

func registerJoystickHandlers() async {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "JoystickHandler")

    let joystickManager = JoystickManager.shared

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidConnect, object: nil, queue: .main
    ) { notification in
        logger.info("got a .GCControllerDidConnect notification")
        if let controller = notification.object as? GCController {

            logger.info("Joystick connected: \(controller)")

            if (controller.extendedGamepad) != nil {
                logger.debug("extended joystick connected, woot")
                Task {
                    await joystickManager.setSixAxisController(controller)
                }
            }
        }
    }

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main
    ) { notification in
        logger.info("Controller disconnected")
        Task {
            await joystickManager.setSixAxisController(nil as GCController?)
        }
    }

    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    }
    )


    await joystickManager.configureACWJoystick()
}
