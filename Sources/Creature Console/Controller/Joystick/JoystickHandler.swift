import Common
import Foundation
import GameController
import OSLog

#if os(macOS)
    import IOKit
#endif

func registerJoystickHandlers(eventLoop: EventLoop) {

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
                joystickManager.sixAxisJoystick.controller = controller
            }
        }
    }

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main
    ) { notification in
        logger.info("Controller disconnected")
        joystickManager.sixAxisJoystick.controller = nil
    }

    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    }
    )


    #if os(macOS)
    joystickManager.acwJoystick.setMatchingCriteria()
    joystickManager.acwJoystick.registerCallbacks()
    joystickManager.acwJoystick.openManager()
    joystickManager.acwJoystick.scheduleWithRunLoop()
    #endif
}
