
import Combine
import Foundation
import OSLog

/**
 IOKit is macOS only. None of this will work on iOS.
 */
#if os(macOS)

import IOKit

// Global C-Function Pointers
func deviceConnectedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice?) {
    guard let context = context else { return }
    let mySelf = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context).takeUnretainedValue()
    mySelf.handleDeviceConnected(device)
}

func deviceDisconnectedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice?) {
    guard let context = context else { return }
    let mySelf = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context).takeUnretainedValue()
    mySelf.handleDeviceDisconnected(device)
}

func inputReportCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue?) {
    guard let context = context else { return }
    let mySelf = Unmanaged<AprilsCreatureWorkshopJoystick>.fromOpaque(context).takeUnretainedValue()
    mySelf.handleInputReport(value)
}


class AprilsCreatureWorkshopJoystick : ObservableObject, Joystick
{
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AprilsCreatureWorkshopJoystick")

    // Use our singleton
    let appState = AppState.shared

    var vendorID: Int
    var productID: Int

    private var manager: IOHIDManager?
    
    @Published var connected: Bool = false
    @Published var serialNumber: String?
    @Published var versionNumber: Int?
    @Published var manufacturer: String?
    var values: [UInt8] = Array(repeating: 0, count: 8)
    
    let objectWillChange = ObservableObjectPublisher()

    /**
     All of these just return false for now until I can get the new hardware made with
     proper buttons.
     */
    @Published var aButtonPressed = false
    @Published var bButtonPressed = false
    @Published var xButtonPressed = false
    @Published var yButtonPressed = false
    
    
    init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        logger.info("AprilsCreatureWorkshopJoystick created for VID \(vendorID) and PID \(productID)")
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
    
    var changesPublisher: AnyPublisher<Void, Never> {
            objectWillChange.eraseToAnyPublisher()
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
            String(kIOHIDProductIDKey): self.productID
        ]

        if let manager = self.manager {
            IOHIDManagerSetDeviceMatching(manager, matchingCriteria as CFDictionary)
            logger.debug("IOHIDManagerSetDeviceMatching created")
        }
    }
    
    func openManager() {
        if let manager = self.manager {
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func registerCallbacks() {
        if let manager = self.manager {
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceConnectedCallback, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceDisconnectedCallback, context)
            IOHIDManagerRegisterInputValueCallback(manager, inputReportCallback, context)
        }
    }
    
    func scheduleWithRunLoop() {
        if let manager = self.manager {
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
    }


    func handleDeviceConnected(_ device: IOHIDDevice?) {
        
        // Update the serial number
        if let device = device {
            self.serialNumber = getSerialNumber(of: device)
        } else {
            serialNumber = nil
        }
        
        // ...and the version
        if let device = device {
            self.versionNumber = getVersion(of: device)
        } else {
            versionNumber = nil
        }
        
        // ...and the manufacturer
        if let device = device {
            self.manufacturer = getManufacturer(of: device)
        } else {
            manufacturer = nil
        }
        
        connected = true
        logger.info("Device connected: \(String(describing: device)) \(device.debugDescription), S/N: \(self.serialNumber ?? "--")")
        
    }

    func handleDeviceDisconnected(_ device: IOHIDDevice?) {
        connected = false
        logger.info("Device disconnected: \(String(describing: device))")
    }

    private func getSerialNumber(of device: IOHIDDevice) -> String? {
        let key = kIOHIDSerialNumberKey as CFString
        guard let serialNumber = IOHIDDeviceGetProperty(device, key) as? String else {
            logger.error("Failed to retrieve serial number")
            return nil
        }
        return serialNumber
    }
    
    private func getVersion(of device: IOHIDDevice) -> Int? {
        let key = kIOHIDVersionNumberKey as CFString
        guard let versionNumberValue = IOHIDDeviceGetProperty(device, key) else {
            logger.error("Failed to retrieve version number")
            return nil
        }
        
        if let versionNumber = versionNumberValue as? Int {
            return versionNumber
        } else {
            logger.error("Version number is not an integer")
            return nil
        }
    }
    
    private func getManufacturer(of device: IOHIDDevice) -> String? {
        let key = kIOHIDManufacturerKey as CFString
        guard let manufacturer = IOHIDDeviceGetProperty(device, key) as? String else {
            logger.error("Failed to retrieve manufacturer")
            return nil
        }
        return manufacturer
    }
    
    
    func handleInputReport(_ value: IOHIDValue?) {

        //logger.trace("Input value received")
        
        // Don't be in here if we don't have a value
        guard let value = value else { return }
        
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let valueInt = UInt8(clamping: IOHIDValueGetIntegerValue(value) + Int((UInt8.max / 2)) + 1)

        /**
         We've gotta be careful of CPU use here. Joysticks can send out a LOT of events, and we don't want the UI needlessly trying to redraw some of our elements on the screen. Instead let's use an ObservableObjectPublisher to only send up updates when we really mean it.
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
        default:
            didChange = false
            break
            }

        // If something changed, tell the main thread to let folks know, please
        if didChange {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
    }
    

}


extension AprilsCreatureWorkshopJoystick {
    static func mock() -> AprilsCreatureWorkshopJoystick {
        let mockJoystick = AprilsCreatureWorkshopJoystick(vendorID: 1234, productID: 5678)

        // Randomly set the values for each axis and control
        mockJoystick.values = mockJoystick.values.map { _ in UInt8(arc4random_uniform(UInt32(UInt8.max))) }
        
        return mockJoystick
    }
}


#endif
