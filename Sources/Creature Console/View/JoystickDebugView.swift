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
                //                Text(
                //                    "S/N: \(serialNumber), Version: \(versionNumber)"
                //                )
                //                .font(.caption2)
                //                .foregroundStyle(.gray)

                Spacer()

                HStack {
                    BarChart(
                        data: Binding(get: { joystickValues }, set: { _ in }),
                        barSpacing: 4.0,
                        maxValue: 255
                    )
                    .frame(height: geometry.size.height * 0.95)
                    .padding()

                    GlassEffectContainer(spacing: 14) {
                        VStack(alignment: .trailing, spacing: 12) {
                            // Values card
                            VStack(alignment: .trailing, spacing: 4) {
                                ForEach(0..<joystickValues.count, id: \.self) { index in
                                    Text("\(index): \(joystickValues[index])")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                            // Button chips
                            Image(systemName: xButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(joystickState.xButtonPressed ? .white : .primary)
                                .padding(8)
                                .glassEffect(
                                    joystickState.xButtonPressed
                                        ? .regular.tint(.blue.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2), value: joystickState.xButtonPressed)

                            Image(systemName: aButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(joystickState.aButtonPressed ? .white : .primary)
                                .padding(8)
                                .glassEffect(
                                    joystickState.aButtonPressed
                                        ? .regular.tint(.green.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2), value: joystickState.aButtonPressed)

                            Image(systemName: bButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(joystickState.bButtonPressed ? .white : .primary)
                                .padding(8)
                                .glassEffect(
                                    joystickState.bButtonPressed
                                        ? .regular.tint(.red.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2), value: joystickState.bButtonPressed)

                            Image(systemName: yButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(joystickState.yButtonPressed ? .white : .primary)
                                .padding(8)
                                .glassEffect(
                                    joystickState.yButtonPressed
                                        ? .regular.tint(.yellow.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2), value: joystickState.yButtonPressed)
                        }
                        .frame(minWidth: 120)
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
