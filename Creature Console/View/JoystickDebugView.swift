//
//  JoystickDebugView.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import SwiftUI
import Logging
import GameController





struct JoystickDebugView: View {
    @ObservedObject var joystick: SixAxisJoystick

    init(joystick: SixAxisJoystick) {
        self.joystick = joystick
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text(joystick.vendor)
                    .font(.headline)
                    .padding()

                Spacer()
                
                BarChart(data: Binding(get: { joystick.axisValues }, set: { _ in }),
                         barSpacing: 4.0,
                         maxValue: 255)
                    .frame(height: geometry.size.height * 0.95)
                    .padding()
            }
            .onAppear {
                joystick.showVirtualJoystickIfNeeded()
            }
            .onDisappear {
                joystick.removeVirtualJoystickIfNeeded()
            }
        }
    }
}

struct JoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickDebugView(joystick: SixAxisJoystick.mock())
    }
}
