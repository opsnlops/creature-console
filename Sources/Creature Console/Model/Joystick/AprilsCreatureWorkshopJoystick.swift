import Common
import Foundation
import OSLog

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
}

/**
 IOKit is macOS only. None of this will work on iOS.
 */
#if os(macOS)

    import IOKit

    /// The Sendable facts about a connected HID device, extracted from the non-Sendable
    /// `IOHIDDevice` before crossing into the main actor.
    struct ACWDeviceInfo: Sendable {
        let serialNumber: String?
        let versionNumber: Int?
        let manufacturer: String?
        let description: String
    }

    /// One parsed HID input event — the Sendable projection of an `IOHIDValue`.
    struct ACWInputReport: Sendable {
        let usagePage: UInt32
        let usage: UInt32
        let integerValue: Int
    }

    // Global C-Function Pointers
    //
    // IOKit invokes these on the main run loop (`scheduleWithRunLoop` registers with
    // `CFRunLoopGetMain()`), so hopping onto the main actor here is an assertion of an
    // existing fact, not a new requirement. The CF values themselves are not Sendable, so
    // each callback reduces them to a Sendable value first and only that crosses over.
    func deviceConnectedCallback(
        context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
        device: IOHIDDevice?
    ) {
        guard let context = context else { return }
        let joystick = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context)
            .takeUnretainedValue()
        let info = device.map { device in
            ACWDeviceInfo(
                serialNumber: IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString)
                    as? String,
                versionNumber: IOHIDDeviceGetProperty(device, kIOHIDVersionNumberKey as CFString)
                    as? Int,
                manufacturer: IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString)
                    as? String,
                description: String(describing: device)
            )
        }
        MainActor.assumeIsolated {
            joystick.handleDeviceConnected(info)
        }
    }

    func deviceDisconnectedCallback(
        context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
        device: IOHIDDevice?
    ) {
        guard let context = context else { return }
        let joystick = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context)
            .takeUnretainedValue()
        let description = String(describing: device)
        MainActor.assumeIsolated {
            joystick.handleDeviceDisconnected(description)
        }
    }

    func inputReportCallback(
        context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
        value: IOHIDValue?
    ) {
        guard let context = context, let value = value else { return }
        let joystick = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context)
            .takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let report = ACWInputReport(
            usagePage: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element),
            integerValue: IOHIDValueGetIntegerValue(value)
        )
        MainActor.assumeIsolated {
            joystick.handleInputReport(report)
        }
    }


    @MainActor
    final class AprilsCreatureWorkshopJoystick: Joystick {

        let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "AprilsCreatureWorkshopJoystick")

        var vendorID: Int
        var productID: Int

        // Created lazily on the main actor: a nonisolated init may only seed isolated
        // storage with Sendable values, and IOHIDManager isn't one.
        private var manager: IOHIDManager?

        var connected: Bool = false
        var serialNumber: String
        var versionNumber: Int
        var manufacturer: String
        var values: [UInt8] = Array(repeating: 127, count: 8)

        // Broadcasting AsyncStream for UI updates
        private var subscribers: [UUID: AsyncStream<JoystickState>.Continuation] = [:]

        var stateUpdates: AsyncStream<JoystickState> {
            AsyncStream { continuation in
                let id = UUID()
                subscribers[id] = continuation

                // Send current state immediately to new subscriber
                continuation.yield(currentState())

                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        self.removeSubscriber(id)
                    }
                }
            }
        }

        private func removeSubscriber(_ id: UUID) {
            subscribers.removeValue(forKey: id)
        }

        private func currentState() -> JoystickState {
            JoystickState(
                connected: connected,
                values: values,
                aButtonPressed: aButtonPressed,
                bButtonPressed: bButtonPressed,
                xButtonPressed: xButtonPressed,
                yButtonPressed: yButtonPressed,
                serialNumber: serialNumber,
                versionNumber: versionNumber,
                manufacturer: manufacturer
            )
        }

        private func publishState(_ state: JoystickState) {
            // Broadcast to all active subscribers
            for continuation in subscribers.values {
                continuation.yield(state)
            }
        }

        /**
     All of these just return false for now until I can get the new hardware made with
     proper buttons.
     */
        var aButtonPressed = false
        var bButtonPressed = false
        var xButtonPressed = false
        var yButtonPressed = false


        nonisolated init(vendorID: Int, productID: Int) {
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = "--"
            self.versionNumber = -1
            self.manufacturer = "unknown"

            logger.info(
                "AprilsCreatureWorkshopJoystick created for VID \(vendorID) and PID \(productID)")
        }

        private func hidManager() -> IOHIDManager {
            if let manager {
                return manager
            }
            let created = IOHIDManagerCreate(
                kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            manager = created
            return created
        }

        /* Joystick Protocol Stuff */
        func poll() {
            // This is a no-op on this joystick, at least for now 😅
        }

        func getValues() -> [UInt8] {
            return values
        }

        func isConnected() -> Bool {
            return connected
        }

        func getAButtonSymbol() -> String {
            return "a.circle"
        }

        func getBButtonSymbol() -> String {
            return "b.circle"
        }

        func getXButtonSymbol() -> String {
            return "X.circle"
        }

        func getYButtonSymbol() -> String {
            return "Y.circle"
        }

        func setMatchingCriteria() {
            let matchingCriteria: [String: Int] = [
                String(kIOHIDVendorIDKey): self.vendorID,
                String(kIOHIDProductIDKey): self.productID,
            ]

            IOHIDManagerSetDeviceMatching(hidManager(), matchingCriteria as CFDictionary)
            logger.debug("IOHIDManagerSetDeviceMatching created")
        }

        func openManager() {
            IOHIDManagerOpen(hidManager(), IOOptionBits(kIOHIDOptionsTypeNone))
        }

        func registerCallbacks() {
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let manager = hidManager()
            IOHIDManagerRegisterDeviceMatchingCallback(
                manager, deviceConnectedCallback, context)
            IOHIDManagerRegisterDeviceRemovalCallback(
                manager, deviceDisconnectedCallback, context)
            IOHIDManagerRegisterInputValueCallback(manager, inputReportCallback, context)
        }

        func scheduleWithRunLoop() {
            IOHIDManagerScheduleWithRunLoop(
                hidManager(), CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }


        func handleDeviceConnected(_ info: ACWDeviceInfo?) {

            // Update the serial number
            if let info = info {

                self.serialNumber = info.serialNumber ?? "--"
                self.versionNumber = info.versionNumber ?? -1
                self.manufacturer = info.manufacturer ?? "unknown"

            }

            connected = true
            logger.info(
                "Device connected: \(info?.description ?? "unknown"), S/N: \(self.serialNumber)"
            )

        }

        func handleDeviceDisconnected(_ description: String) {
            connected = false
            logger.info("Device disconnected: \(description)")
        }


        func handleInputReport(_ report: ACWInputReport) {

            let usagePage = report.usagePage
            let usage = report.usage
            let valueInt = UInt8(
                clamping: report.integerValue + Int((UInt8.max / 2)) + 1)

            /**
         We've gotta be careful of CPU use here. Joysticks can send out a LOT of events, and we
         don't want the UI needlessly trying to redraw some of our elements on the screen.
         Only publish when a value actually changed.
         */

            var didChange = false
            switch (usagePage, usage) {
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_X)):
                if self.values[0] != valueInt {
                    self.values[0] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Y)):
                if self.values[1] != valueInt {
                    self.values[1] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Z)):
                if self.values[2] != valueInt {
                    self.values[2] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rx)):
                if self.values[3] != valueInt {
                    self.values[3] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Ry)):
                if self.values[4] != valueInt {
                    self.values[4] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rz)):
                if self.values[5] != valueInt {
                    self.values[5] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Dial)):
                if self.values[6] != valueInt {
                    self.values[6] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Wheel)):
                if self.values[7] != valueInt {
                    self.values[7] = valueInt
                    didChange = true
                }
            case (UInt32(kHIDPage_Button), 1):
                let buttonPressed = (report.integerValue != 0)
                if self.aButtonPressed != buttonPressed {
                    self.aButtonPressed = buttonPressed
                    didChange = true
                }
            case (UInt32(kHIDPage_Button), 2):
                let buttonPressed = (report.integerValue != 0)
                if self.bButtonPressed != buttonPressed {
                    self.bButtonPressed = buttonPressed
                    didChange = true
                }
            default:
                didChange = false
            }

            // If something changed, publish the new state
            if didChange {
                publishState(currentState())
            }

        }

        func updateJoystickLight(activity: Activity) {
            // AprilsCreatureWorkshopJoystick doesn't have programmable lights,
            // but we need to implement this to conform to the Joystick protocol
            // Could potentially control external LEDs here in the future
        }

    }


    extension AprilsCreatureWorkshopJoystick {
        static func mock() -> AprilsCreatureWorkshopJoystick {
            let mockJoystick = AprilsCreatureWorkshopJoystick(vendorID: 1234, productID: 5678)

            // Randomly set the values for each axis and control
            mockJoystick.values = mockJoystick.values.map { _ in
                UInt8(arc4random_uniform(UInt32(UInt8.max)))
            }

            return mockJoystick
        }
    }


#endif
