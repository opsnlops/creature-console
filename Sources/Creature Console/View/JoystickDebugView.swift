import Common
import OSLog
import SwiftUI

//#if os(macOS)

struct JoystickDebugView: View {

    @ObservedObject var joystickManager = JoystickManager.shared

    var body: some View {
        GeometryReader { geometry in
            VStack {

                Spacer()

                Text("🎮 \(joystickManager.manufacturer ?? "Unknown manufacturer")")
                    .font(.headline)
                Text(
                    "S/N: \(joystickManager.serialNumber ?? "Unknown SN"), Version: \(joystickManager.versionNumber ?? 0)"
                )
                .font(.caption2)
                .foregroundStyle(.gray)

                Spacer()

                HStack {
                    BarChart(
                        data: Binding(get: { joystickManager.values }, set: { _ in }),
                        barSpacing: 4.0,
                        maxValue: 255
                    )
                    .frame(height: geometry.size.height * 0.95)
                    .padding()

                    VStack {
                        ForEach(0..<joystickManager.values.count, id: \.self) { index in
                            Text("\(index): \(joystickManager.values[index])")
                        }


                        Image(systemName: joystickManager.getActiveJoystick().getXButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickManager.xButtonPressed ? .accentColor : .primary)


                        Image(systemName: joystickManager.getActiveJoystick().getAButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickManager.aButtonPressed ? .accentColor : .primary)


                        Image(systemName: joystickManager.getActiveJoystick().getBButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickManager.bButtonPressed ? .accentColor : .primary)


                        Image(systemName: joystickManager.getActiveJoystick().getYButtonSymbol())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickManager.yButtonPressed ? .accentColor : .primary)

                    }

                    Spacer()

                }
            }
        }
    }
}


struct JoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickDebugView()
    }
}


//#endif
