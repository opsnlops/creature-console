import Common
import OSLog
import SwiftUI

#if os(iOS)
    import UIKit
#endif

//#if os(macOS)

struct JoystickDebugView: View {

    @Environment(ConsoleStore.self) private var console
    @State private var joystickValues: [UInt8] = Array(repeating: 0, count: 8)
    @State private var connected: Bool = false
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
                                .foregroundStyle(
                                    console.joystick.xButtonPressed ? .white : .primary
                                )
                                .padding(8)
                                .glassEffect(
                                    console.joystick.xButtonPressed
                                        ? .regular.tint(.blue.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2),
                                    value: console.joystick.xButtonPressed)

                            Image(systemName: aButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    console.joystick.aButtonPressed ? .white : .primary
                                )
                                .padding(8)
                                .glassEffect(
                                    console.joystick.aButtonPressed
                                        ? .regular.tint(.green.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2),
                                    value: console.joystick.aButtonPressed)

                            Image(systemName: bButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    console.joystick.bButtonPressed ? .white : .primary
                                )
                                .padding(8)
                                .glassEffect(
                                    console.joystick.bButtonPressed
                                        ? .regular.tint(.red.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2),
                                    value: console.joystick.bButtonPressed)

                            Image(systemName: yButtonSymbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    console.joystick.yButtonPressed ? .white : .primary
                                )
                                .padding(8)
                                .glassEffect(
                                    console.joystick.yButtonPressed
                                        ? .regular.tint(.yellow.opacity(0.35)).interactive()
                                        : .regular.interactive(),
                                    in: .circle
                                )
                                .animation(
                                    .easeInOut(duration: 0.2),
                                    value: console.joystick.yButtonPressed)
                        }
                        .frame(minWidth: 120)
                    }

                    Spacer()

                }
            }
        }
        .task {
            // Button *state* now comes from ConsoleStore, but the SF Symbol names depend on which
            // physical joystick is active — data the store doesn't carry — so keep a subscription
            // just to refresh the symbols whenever the joystick state changes.
            for await _ in await JoystickManager.shared.stateUpdates {
                aButtonSymbol = JoystickManager.shared.getAButtonSymbol()
                bButtonSymbol = JoystickManager.shared.getBButtonSymbol()
                xButtonSymbol = JoystickManager.shared.getXButtonSymbol()
                yButtonSymbol = JoystickManager.shared.getYButtonSymbol()
            }
        }
        .task {
            // Periodically update values and metadata from the JoystickManager actor
            while !Task.isCancelled {
                let manager = JoystickManager.shared
                joystickValues = await manager.getValues()
                connected = await manager.isConnected
                manufacturer = await manager.getManufacturer ?? "Unknown manufacturer"
                serialNumber = await manager.getSerialNumber ?? "Unknown SN"
                versionNumber = await manager.getVersionNumber ?? 0

                try? await Task.sleep(for: .milliseconds(50))  // 20fps update rate for real-time debugging
            }
        }
    }
}


#Preview {
    JoystickDebugView()
        .environment(ConsoleStore.shared)
}


//#endif
