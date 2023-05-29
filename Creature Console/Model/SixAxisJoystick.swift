//
//  SixAxisJoystick.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import Foundation
import GameController
import Logging
import Combine

class Axis : ObservableObject, CustomStringConvertible {
    var axisType : AxisType = .gamepad
    @Published var name: String = ""
    @Published var value: UInt8 = 127
        
    var rawValue: Float = 0 {
        didSet {
            
            var mappedvalue = Float(0.0)
            
            switch(axisType) {
            case(.gamepad):
                // The raw value is a value of -1.0 to 1.0, where the center is 0. Let's map this to a value that we normally use on our creature joysticks
                mappedvalue = Float(UInt8.max) * Float((rawValue + 1.0)/2)
                
            default:
                mappedvalue = Float(UInt8.max) * Float(rawValue)
            }
  
            value = UInt8(round(mappedvalue))
        }
    }
    
    var description: String {
        return String(value)
    }
    
    enum AxisType : CustomStringConvertible {
      case gamepad
      case trigger
        
        var description: String {
            switch self {
            case .gamepad:
                return "Gamepad"
            case .trigger:
                return "Trigger"
            }
        }
    }
}


class SixAxisJoystick : ObservableObject {
    @Published var axises : [Axis]
    @Published var aButtonPressed = false
    @Published var bButtonPressed = false
    @Published var xButtonPressed = false
    @Published var yButtonPressed = false
    
    var appState : AppState
    var controller : GCController?
    let objectWillChange = ObservableObjectPublisher()
    let logger = Logger(label: "SixAxisJoystick")
    
    private var cancellables: Set<AnyCancellable> = []
    
    

    
#if os(iOS)
    var virtualJoysick = VirtualJoystick()
    var virtualJoystickConnected = false
#endif
    
    var vendor : String {
        controller?.vendorName ?? "🎮"
    }
    
    init(appState: AppState) {
        self.axises = []
        self.appState = appState
        
        for _ in 0...5 {
            self.axises.append(Axis())
        }
        
        // Axies 4 and 5 are triggers
        self.axises[4].axisType = .trigger
        self.axises[5].axisType = .trigger
        self.axises[4].value = 0
        self.axises[5].value = 0
        
        // Pay attention to the joystick, even when in the background
        GCController.shouldMonitorBackgroundEvents = true
        
        // Update the lights when there's a change in app state
        appState.$currentActivity.sink { [weak self] newActivity in
            self?.updateJoystickLight(activity: newActivity)
        }.store(in: &cancellables)

    }
    
    deinit {
        for cancellable in cancellables {
            cancellable.cancel()
        }
    }
    
    var axisValues: [UInt8] {
        return axises.map { $0.value }
    }
    
    func updateJoystickLight(activity: AppState.Activity) {
            // Update the light when this changes
            guard let controller = GCController.current else { return }
            controller.light?.color = activity.color
    }
    
    func showVirtualJoystickIfNeeded() {
        
        #if os(iOS)
        if GCController.controllers().isEmpty {
            logger.info("creating virtual joystick")
            virtualJoysick.create()
            virtualJoysick.connect()
            virtualJoystickConnected = true
        }
        #endif
        
    }
    
    func removeVirtualJoystickIfNeeded() {
        #if os(iOS)
        if virtualJoystickConnected {
            virtualJoysick.disconnect()
            virtualJoystickConnected = false
            logger.info("disconnecting virtual joystick")
        }
        #endif
    }
    
    
    func poll() {
        
        if let joystick = controller?.extendedGamepad {
            
            var didChange = false
            
            if axises[0].rawValue != joystick.leftThumbstick.xAxis.value {
                axises[0].rawValue = joystick.leftThumbstick.xAxis.value
                didChange = true
            }
            
            if axises[1].rawValue != joystick.leftThumbstick.yAxis.value {
                axises[1].rawValue = joystick.leftThumbstick.yAxis.value
                didChange = true
            }
            
            if axises[2].rawValue != joystick.rightThumbstick.xAxis.value {
                axises[2].rawValue = joystick.rightThumbstick.xAxis.value
                didChange = true
            }
            
            if axises[3].rawValue != joystick.rightThumbstick.yAxis.value {
                axises[3].rawValue = joystick.rightThumbstick.yAxis.value
                didChange = true
            }
            
            if axises[4].rawValue != joystick.leftTrigger.value {
                axises[4].rawValue = joystick.leftTrigger.value
                didChange = true
            }
            
            if axises[5].rawValue != joystick.rightTrigger.value {
                axises[5].rawValue = joystick.rightTrigger.value
                didChange = true
            }
            
            if joystick.buttonA.isPressed != self.aButtonPressed {
                self.aButtonPressed = joystick.buttonA.isPressed
                didChange = true
            }
            
            if joystick.buttonB.isPressed != self.bButtonPressed {
                self.bButtonPressed = joystick.buttonB.isPressed
                didChange = true
            }
            
            if joystick.buttonX.isPressed != self.xButtonPressed {
                self.xButtonPressed = joystick.buttonX.isPressed
                didChange = true
            }
            
            if joystick.buttonY.isPressed != self.yButtonPressed {
                self.yButtonPressed = joystick.buttonY.isPressed
                didChange = true
            }
            
            logger.debug("joystick polling done")
       
            // If there's a change to be propogated out, let the main thread do it
            if didChange {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
        else {
            logger.info("skipping polling because not extended gamepad")
        }
        
    }
    
}


/**
 Since we're the ones that care about color, define the colors here
 */
extension AppState.Activity {
    var color: GCColor {
        switch self {
        case .idle:
            return GCColor(red: 0.0, green: 0.0, blue: 1.0)
        case .streaming:
            return GCColor(red: 0.0, green: 1.0, blue: 0.0)
        case .recording:
            return GCColor(red: 1.0, green: 0.0, blue: 0.0)
        case .preparingToRecord:
            return GCColor(red: 1.0, green: 1.0, blue: 0.0)
        }
    }
}

extension SixAxisJoystick {
    static func mock() -> SixAxisJoystick {
        let joystick = SixAxisJoystick(appState: .mock())
        
        for axis in joystick.axises {
            axis.value = UInt8(arc4random_uniform(UInt32(UInt8.max)))
        }
        
        return joystick
    }
}
