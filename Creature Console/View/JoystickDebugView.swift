
import Combine
import SwiftUI
import OSLog
import GameController


struct JoystickDebugView: View {
    var joystick: Joystick
    @State private var values: [UInt8] = []
    @State private var xButtonPressed = false
    @State private var yButtonPressed = false
    @State private var aButtonPressed = false
    @State private var bButtonPressed = false

    init(joystick: Joystick) {
        self.joystick = joystick
        self._values = State(initialValue: joystick.getValues())
        self._aButtonPressed = State(initialValue: joystick.aButtonPressed)
        self._bButtonPressed = State(initialValue: joystick.bButtonPressed)
        self._xButtonPressed = State(initialValue: joystick.xButtonPressed)
        self._yButtonPressed = State(initialValue: joystick.yButtonPressed)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                
                Spacer()
                
                Text(joystick.manufacturer ?? "Unknown")
                    .font(.headline)

                Spacer()
                
                HStack {
                    BarChart(data: Binding(get: { joystick.getValues() }, set: { _ in }),
                             barSpacing: 4.0,
                             maxValue: 255)
                    .frame(height: geometry.size.height * 0.95)
                    .padding()
                    
                    VStack {
                        Spacer()
                        
                        Image(systemName: joystick.getXButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(xButtonPressed ? .accentColor : .primary)
                        
                        Spacer()
                        
                        Image(systemName: joystick.getAButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(aButtonPressed ? .accentColor : .primary)

                        Spacer()

                        Image(systemName: joystick.getBButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(bButtonPressed ? .accentColor : .primary)

                        Spacer()
                                                
                        Image(systemName: joystick.getYButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(yButtonPressed ? .accentColor : .primary)

                        Spacer()
                    }
                    .frame(width: 100.0)
                }
            }
            .onAppear {
                if let j = joystick as? SixAxisJoystick {
                    j.showVirtualJoystickIfNeeded()
                }
            }
            .onDisappear {
                if let j = joystick as? SixAxisJoystick {
                    j.removeVirtualJoystickIfNeeded()
                }
            }
            .onReceive(joystick.changesPublisher) {
                self.values = joystick.getValues()
                self.aButtonPressed = joystick.aButtonPressed
                self.bButtonPressed = joystick.bButtonPressed
                self.xButtonPressed = joystick.xButtonPressed
                self.yButtonPressed = joystick.yButtonPressed
            }
        }
    }
}

struct JoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickDebugView(joystick: SixAxisJoystick.mock())
    }
}
