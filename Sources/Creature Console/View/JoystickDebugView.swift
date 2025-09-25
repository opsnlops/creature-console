import Common
import OSLog
import SwiftUI

#if os(iOS)
import UIKit
#endif

//#if os(macOS)

struct JoystickDebugView: View {

    @State private var joystickValues: [UInt8] = Array(repeating: 0, count: 8)
    @State private var connected: Bool = false
    @State private var joystickState = JoystickManagerState(
        aButtonPressed: false, bButtonPressed: false, xButtonPressed: false, yButtonPressed: false,
        selectedJoystick: .none)
    @State private var aButtonSymbol: String = "a.circle"
    @State private var bButtonSymbol: String = "b.circle"
    @State private var xButtonSymbol: String = "x.circle"
    @State private var yButtonSymbol: String = "y.circle"
    @State private var manufacturer: String = "Unknown manufacturer"
    @State private var serialNumber: String = "Unknown SN"
    @State private var versionNumber: Int = 0

    var body: some View {
        GeometryReader { geometry in
            VStack {

                Spacer()

                Text("🎮 \(manufacturer)")
                    .font(.headline)
                Text(
                    "S/N: \(serialNumber), Version: \(versionNumber)"
                )
                .font(.caption2)
                .foregroundStyle(.gray)

                Spacer()

                HStack {
                    BarChart(
                        data: Binding(get: { joystickValues }, set: { _ in }),
                        barSpacing: 4.0,
                        maxValue: 255
                    )
                    .frame(height: geometry.size.height * 0.95)
                    .padding()

                    VStack {
                        ForEach(0..<joystickValues.count, id: \.self) { index in
                            Text("\(index): \(joystickValues[index])")
                        }


                        Image(systemName: xButtonSymbol)  // X button symbol
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickState.xButtonPressed ? .accentColor : .primary)


                        Image(systemName: aButtonSymbol)  // A button symbol
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickState.aButtonPressed ? .accentColor : .primary)


                        Image(systemName: bButtonSymbol)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickState.bButtonPressed ? .accentColor : .primary)


                        Image(systemName: yButtonSymbol)  // Y button symbol
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100 / 2.5)
                            .foregroundColor(
                                joystickState.yButtonPressed ? .accentColor : .primary)

                    }

                    Spacer()

                }
            }
        }
        .task {
            // Update button states from AsyncStream
            for await state in await JoystickManager.shared.stateUpdates {
                await MainActor.run {
                    joystickState = state
                }

                // Update button symbols when joystick state changes
                let aSymbol = await JoystickManager.shared.getAButtonSymbol()
                let bSymbol = await JoystickManager.shared.getBButtonSymbol()
                let xSymbol = await JoystickManager.shared.getXButtonSymbol()
                let ySymbol = await JoystickManager.shared.getYButtonSymbol()
                await MainActor.run {
                    aButtonSymbol = aSymbol
                    bButtonSymbol = bSymbol
                    xButtonSymbol = xSymbol
                    yButtonSymbol = ySymbol
                }
            }
        }
        .task {
            // Periodically update values and metadata from the JoystickManager actor
            while !Task.isCancelled {
                let manager = JoystickManager.shared
                let values = await manager.getValues()
                let isConnected = await manager.isConnected
                let mfg = await manager.getManufacturer ?? "Unknown manufacturer"
                let sn = await manager.getSerialNumber ?? "Unknown SN"
                let version = await manager.getVersionNumber ?? 0

                await MainActor.run {
                    joystickValues = values
                    connected = isConnected
                    manufacturer = mfg
                    serialNumber = sn
                    versionNumber = version
                }

                try? await Task.sleep(for: .milliseconds(50))  // 20fps update rate for real-time debugging
            }
        }
#if os(iOS)
        .toolbar(id: "global-bottom-status") {
            if UIDevice.current.userInterfaceIdiom == .phone {
                ToolbarItem(id: "status", placement: .bottomBar) {
                    BottomStatusToolbarContent()
                }
            }
        }
#endif
    }
}


struct JoystickDebugView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickDebugView()
    }
}


//#endif

