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
                x: .value("Axis", "Axis 0"),
                y: .value("Value", axis0.value)
            )
            BarMark(
                x: .value("Axis", "Axis 1"),
                y: .value("Value", axis1.value)
            )
            BarMark(
                x: .value("Axis", "Axis 2"),
                y: .value("Value", axis2.value)
            )
            BarMark(
                x: .value("Axis", "Axis 3"),
                y: .value("Value", axis3.value)
            )
            BarMark(
                x: .value("Axis", "Axis 4"),
                y: .value("Value", axis4.value)
            )
            BarMark(
                x: .value("Axis", "Axis 5"),
                y: .value("Value", axis5.value)
            )
        }
        .chartYScale(domain: 0 ... 255)
        .chartForegroundStyleScale([
            "Axis 0": .red,
            "Axis 1": .orange,
            "Axis 2": .yellow,
            "Axis 3": .green,
            "Axis 4": .blue,
            "Axis 5": .purple
        ])
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
