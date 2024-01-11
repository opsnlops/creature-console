
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


class AprilsCreatureWorkshopJoystick : ObservableObject
{
 
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AprilsCreatureWorkshopJoystick")

    var vendorID: Int
    var productID: Int
    var appState : AppState
    private var manager: IOHIDManager?
    
    @Published var values: [UInt8] = Array(repeating: 0, count: 8)

    init(appState: AppState, vendorID: Int, productID: Int) {
        self.appState = appState
        self.vendorID = vendorID
        self.productID = productID
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        logger.info("AprilsCreatureWorkshopJoystick created for VID \(vendorID) and PID \(productID)")
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
        logger.info("Device connected: \(String(describing: device)) \(device.debugDescription)")
    }

    func handleDeviceDisconnected(_ device: IOHIDDevice?) {
        logger.info("Device disconnected: \(String(describing: device))")
    }

    func handleInputReport(_ value: IOHIDValue?) {

        //logger.trace("Input value received")
        
        // Don't be in here if we don't have a value
        guard let value = value else { return }
        
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let valueInt = IOHIDValueGetIntegerValue(value) + Int((UInt8.max / 2)) + 1

        switch (usagePage, usage) {
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_X)):
            self.values[0] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Y)):
            self.values[1] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Z)):
            self.values[2] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rx)):
            self.values[3] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Ry)):
            self.values[4] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rz)):
            self.values[5] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Dial)):
            self.values[6] = UInt8(clamping: valueInt)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Wheel)):
            self.values[7] = UInt8(clamping: valueInt)
        default:
            break
            }

        }
    


}


extension AprilsCreatureWorkshopJoystick {
    static func mock(appState: AppState) -> AprilsCreatureWorkshopJoystick {
        let mockJoystick = AprilsCreatureWorkshopJoystick(appState: appState, vendorID: 1234, productID: 5678)
        
        // Randomly set the values for each axis and control
        mockJoystick.values = mockJoystick.values.map { _ in UInt8(arc4random_uniform(UInt32(UInt8.max))) }
        
        return mockJoystick
    }
}


#endif
