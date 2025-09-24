import Common
import Foundation
import GameController
import OSLog

#if os(macOS)
    import IOKit
#endif

struct SendableGCController: @unchecked Sendable {
    let controller: GCController
}

func registerJoystickHandlers() async {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "JoystickHandler")

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidConnect, object: nil, queue: .main
    ) { notification in
        logger.info("got a .GCControllerDidConnect notification")
        if let controller = notification.object as? GCController {

            logger.info("Joystick connected: \(controller)")

            if (controller.extendedGamepad) != nil {
                logger.debug("extended joystick connected, woot")
                let sendableController = SendableGCController(controller: controller)
                Task { [sendableController] in
                    await JoystickManager.shared.setSixAxisController(sendableController)
                }
            }
        }
    }

    NotificationCenter.default.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main
    ) { notification in
        logger.info("Controller disconnected")
        Task {
            await JoystickManager.shared.setSixAxisController(nil)
        }
    }

    GCController.startWirelessControllerDiscovery(completionHandler: {
        logger.info("Finished wireless controller discovery")
    }
    )

    await JoystickManager.shared.configureACWJoystick()
}
