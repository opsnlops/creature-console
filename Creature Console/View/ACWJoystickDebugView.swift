
import SwiftUI
import OSLog

#if os(macOS)

struct ACWJoystickDebugView: View {
    @ObservedObject var joystick: AprilsCreatureWorkshopJoystick

    init(joystick: AprilsCreatureWorkshopJoystick) {
        self.joystick = joystick
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("Our Joystick (maybe serial?)")
                    .font(.headline)
                    .padding()

                Spacer()
                
                HStack {
                    BarChart(data: Binding(get: { joystick.values }, set: { _ in }),
                             barSpacing: 4.0,
                             maxValue: 255)
                    .frame(height: geometry.size.height * 0.95)
                    .padding()
                    }
                }
            }
        }
    }


struct ACWJoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        ACWJoystickDebugView(joystick: AprilsCreatureWorkshopJoystick.mock(appState: .mock()))
    }
}


#endif
