import Common
import Foundation
import GameController
import OSLog

#if os(macOS)
    import IOKit
#endif

func registerJoystickHandlers() async {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "JoystickHandler")

    // These observers are registered on the main queue, so the closures run on the main
    // thread; `assumeIsolated` states that fact to the compiler, which lets the (main-actor
    // affine) GCController flow into the manager without a Sendable wrapper.
    NotificationCenter.default.addObserver(
        forName: .GCControllerDidConnect, object: nil, queue: .main
    ) { notification in
        logger.info("got a .GCControllerDidConnect notification")
        if let controller = notification.object as? GCController {

            logger.info("Joystick connected: \(controller)")

            if (controller.extendedGamepad) != nil {
                logger.debug("extended joystick connected, woot")
                MainActor.assumeIsolated {
                    JoystickManager.shared.refreshSixAxisController()
                }
            }
        }
    }

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main
    ) { notification in
        logger.info("Controller disconnected")
        MainActor.assumeIsolated {
            JoystickManager.shared.refreshSixAxisController()
        }
    }

    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    }
    )

    await JoystickManager.shared.configureACWJoystick()
}
