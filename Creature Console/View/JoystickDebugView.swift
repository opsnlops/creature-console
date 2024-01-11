//
//  JoystickDebugView.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import SwiftUI
import OSLog
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
                
                HStack {
                    BarChart(data: Binding(get: { joystick.axisValues }, set: { _ in }),
                             barSpacing: 4.0,
                             maxValue: 255)
                    .frame(height: geometry.size.height * 0.95)
                    .padding()
                    
                    VStack {
                        Spacer()
                        
                        Image(systemName: joystick.controller?.extendedGamepad?.buttonX.sfSymbolsName ?? "x.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(joystick.xButtonPressed ? .accentColor : .primary)
                        
                        Spacer()
                        
                        Image(systemName: joystick.controller?.extendedGamepad?.buttonA.sfSymbolsName ?? "a.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(joystick.aButtonPressed ? .accentColor : .primary)

                        Spacer()

                        Image(systemName: joystick.controller?.extendedGamepad?.buttonB.sfSymbolsName ?? "b.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(joystick.bButtonPressed ? .accentColor : .primary)

                        Spacer()
                                                
                        Image(systemName: joystick.controller?.extendedGamepad?.buttonY.sfSymbolsName ?? "y.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(joystick.yButtonPressed ? .accentColor : .primary)

                        Spacer()
                    }
                    .frame(width: 100.0)
                }
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
