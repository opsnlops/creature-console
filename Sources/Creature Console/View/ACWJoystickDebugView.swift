
import SwiftUI
import OSLog
import Common

#if os(macOS)

struct ACWJoystickDebugView: View {
    @ObservedObject var joystick: AprilsCreatureWorkshopJoystick

    init(joystick: AprilsCreatureWorkshopJoystick) {
        self.joystick = joystick
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                
                Spacer()
                
                Text("🎮 \(joystick.manufacturer ?? "Unknown manufacturer")")
                    .font(.headline)
                Text("S/N: \(joystick.serialNumber ?? "Unknown SN"), Version: \(joystick.versionNumber ?? 0)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
    
                Spacer()
                
                HStack {
                    BarChart(data: Binding(get: { joystick.values }, set: { _ in }),
                             barSpacing: 4.0,
                             maxValue: 255)
                    .frame(height: geometry.size.height * 0.95)
                    .padding()
                    
                    VStack {
                        ForEach(0..<joystick.values.count, id: \.self) { index in
                            Text("\(index): \(joystick.values[index])")
                            }
                        
                        }
                    
                    Spacer()
                    
                    }
                }
            }
        }
    }


struct ACWJoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        ACWJoystickDebugView(joystick: AprilsCreatureWorkshopJoystick.mock())
    }
}


#endif
