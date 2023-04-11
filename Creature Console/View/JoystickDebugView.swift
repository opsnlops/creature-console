//
//  JoystickDebugView.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import SwiftUI
import Logging
import Charts
import GameController


struct JoyStickChart: View {
    var joystick : SixAxisJoystick
    
    @ObservedObject var axis0 : Axis
    @ObservedObject var axis1 : Axis
    @ObservedObject var axis2 : Axis
    @ObservedObject var axis3 : Axis
    @ObservedObject var axis4 : Axis
    @ObservedObject var axis5 : Axis
    
    init(joystick: SixAxisJoystick)
    {
        self.joystick = joystick
        self.axis0 = joystick.axises[0]
        self.axis1 = joystick.axises[1]
        self.axis2 = joystick.axises[2]
        self.axis3 = joystick.axises[3]
        self.axis4 = joystick.axises[4]
        self.axis5 = joystick.axises[5]
        
    }
    
    var body: some View {
        Chart {
            BarMark(
                x: .value("Axis 0", "Axis 0"),
                y: .value("Value", axis0.value)
            )
            BarMark(
                x: .value("Axis 1", "Axis 1"),
                y: .value("Value", axis1.value)
            )
            BarMark(
                x: .value("Axis 2", "Axis 2"),
                y: .value("Value", axis2.value)
            )
            BarMark(
                x: .value("Axis 3", "Axis 3"),
                y: .value("Value", axis3.value)
            )
            BarMark(
                x: .value("Axis 4", "Axis 4"),
                y: .value("Value", axis4.value)
            )
            BarMark(
                x: .value("Axis 5", "Axis 5"),
                y: .value("Value", axis5.value)
            )
        }
    }
}



struct JoystickDebugView: View {
        
    @ObservedObject var joystick: SixAxisJoystick
    
    #if os(iOS)
        var virtualJoysick : VirtualJoystick
    #endif
    
    let logger = Logger(label: "JoystickDebugView")
    
    init(joystick: SixAxisJoystick) {
        self.joystick = joystick
        
#if os(iOS)
        self.virtualJoysick = VirtualJoystick()
#endif
    }
    
    var body: some View {
        
        VStack {
            JoyStickChart(joystick: joystick)
        }
#if os(iOS)
        .onAppear {
            if GCController.controllers().isEmpty {
                print("IT WAS EMPTY")
                virtualJoysick.create()
            }
            else {
                print("IT WAS NOT EMPTY")
            }
            virtualJoysick.connect()
        }
        .onDisappear {
           virtualJoysick.disconnect()
        }
#endif
    }
}

struct JoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        Text("HI")
    }
}
