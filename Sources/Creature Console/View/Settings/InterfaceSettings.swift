import Common
import OSLog
import SwiftUI

struct InterfaceSettings: View {
    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 0
    @AppStorage("mouthImportDefaultAxis") private var defaultMouthAxis: Int = 2

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "InterfaceSettings")

    var body: some View {
        ZStack {
            // Liquid Glass background
            LiquidGlass()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Interface Settings")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 8)

                // Card 1: Mouth Import Defaults
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mouth Import", systemImage: "waveform.path")
                        .font(.headline)
                    HStack {
                        Text("Default Axis")
                        Spacer()
                        Stepper(value: Binding<Double>(
                            get: { Double(defaultMouthAxis) },
                            set: { defaultMouthAxis = Int($0) }
                        ), in: 0...15, step: 1) {
                            Text("Axis \(defaultMouthAxis)")
                        }
                        .frame(maxWidth: 180)
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }

                // Card 2: Server Logs
                VStack(alignment: .leading, spacing: 12) {
                    Label("Server Logs", systemImage: "text.alignleft")
                        .font(.headline)
                    HStack {
                        Text("Scrollback Lines")
                        Spacer()
                        Slider(value: Binding<Double>(
                            get: { Double(serverLogsScrollBackLines) },
                            set: { serverLogsScrollBackLines = Int($0) }
                        ), in: 10...200, step: 10)
                        .frame(maxWidth: 280)
                        Text("\(serverLogsScrollBackLines)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

struct InterfaceSettings_Previews: PreviewProvider {
    static var previews: some View {
        InterfaceSettings()
    }
}

struct LiquidGlass: View {
    var body: some View {
        Rectangle()
            .fill(.thinMaterial)
            .overlay(
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blendMode(.screen)
            )
    }
}
