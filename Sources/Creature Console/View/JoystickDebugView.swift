import Common
import OSLog
import SwiftUI

extension SelectedJoystick {
    fileprivate var displayName: String {
        switch self {
        case .sixAxis: return "System Gamepad"
        case .acw: return "ACW Joystick"
        case .none: return "None"
        }
    }
}

/// The joystick debugging surface: everything the hardware is reporting, live.
///
/// Fully event-driven — one `stateUpdates` subscription drives the whole view, so what's on
/// screen is exactly what the event loop is sampling (issue #59). No polling loops.
struct JoystickDebugView: View {

    @State private var state = JoystickManagerState.initial
    @State private var aButtonSymbol: String = "a.circle"
    @State private var bButtonSymbol: String = "b.circle"
    @State private var xButtonSymbol: String = "x.circle"
    @State private var yButtonSymbol: String = "y.circle"

    var body: some View {
        Group {
            if state.connected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .task {
            for await newState in await JoystickManager.shared.stateUpdates {
                state = newState
                // Symbol names depend on which physical joystick is active — a main-actor
                // lookup, but only on state changes, never per frame.
                aButtonSymbol = JoystickManager.shared.getAButtonSymbol()
                bButtonSymbol = JoystickManager.shared.getBButtonSymbol()
                xButtonSymbol = JoystickManager.shared.getXButtonSymbol()
                yButtonSymbol = JoystickManager.shared.getYButtonSymbol()
            }
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {

                header

                HStack(alignment: .center) {
                    BarChart(
                        data: Binding(get: { state.values }, set: { _ in }),
                        barSpacing: 4.0,
                        maxValue: 255
                    )
                    .frame(height: geometry.size.height * 0.75)
                    .padding()

                    GlassEffectContainer(spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            axisReadout

                            VStack(alignment: .trailing, spacing: 12) {
                                buttonChip(
                                    symbol: xButtonSymbol, pressed: state.xButtonPressed,
                                    tint: .blue)
                                buttonChip(
                                    symbol: aButtonSymbol, pressed: state.aButtonPressed,
                                    tint: .green)
                                buttonChip(
                                    symbol: bButtonSymbol, pressed: state.bButtonPressed,
                                    tint: .red)
                                buttonChip(
                                    symbol: yButtonSymbol, pressed: state.yButtonPressed,
                                    tint: .yellow)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Connection chip
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.green.opacity(0.2)), in: .capsule)

            // Which joystick is active — the first thing to check when input looks wrong
            HStack(spacing: 6) {
                Image(systemName: state.selectedJoystick.getBButtonSymbol())
                Text(state.selectedJoystick.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)

            VStack(alignment: .leading, spacing: 2) {
                Text("🎮 \(state.manufacturer ?? "Unknown manufacturer")")
                    .font(.headline)
                Text(deviceDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var deviceDetail: String {
        var parts: [String] = []
        if let serial = state.serialNumber {
            parts.append("S/N \(serial)")
        }
        if let version = state.versionNumber, version > 0 {
            parts.append("v\(version)")
        }
        return parts.isEmpty ? "No device details reported" : parts.joined(separator: " · ")
    }

    /// Per-axis readout: decimal and hex, monospaced so values don't jitter as they change.
    private var axisReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(0..<state.values.count, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index)")
                        .foregroundStyle(.tertiary)
                    Text("\(state.values[index])")
                        .frame(minWidth: 34, alignment: .trailing)
                    Text(String(format: "0x%02X", state.values[index]))
                        .foregroundStyle(.secondary)
                }
                .font(.footnote.monospacedDigit())
            }
        }
        .padding(10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }

    private func buttonChip(symbol: String, pressed: Bool, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(pressed ? .white : .primary)
            .padding(8)
            .glassEffect(
                pressed
                    ? .regular.tint(tint.opacity(0.35)).interactive()
                    : .regular.interactive(),
                in: .circle
            )
            .animation(.easeInOut(duration: 0.2), value: pressed)
    }

    // MARK: - Disconnected

    private var disconnectedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No joystick connected")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(
                "Connect a gamepad or the ACW joystick and its state will appear here in real time"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}


#Preview {
    JoystickDebugView()
        .environment(ConsoleStore.shared)
}
