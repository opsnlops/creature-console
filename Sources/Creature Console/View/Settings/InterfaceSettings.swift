import Common
import OSLog
import SwiftUI

struct InterfaceSettings: View {
    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 0
    @AppStorage("mouthImportDefaultAxis") private var defaultMouthAxis: Int = 2
    @AppStorage("audioVolume") private var audioVolume: Double = 1.0

    #if os(tvOS)
        @State private var tvDefaultMouthAxisText: String = ""
        @State private var tvServerLogsScrollbackText: String = ""
        @State private var tvAudioVolumeText: String = ""
    #endif

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "InterfaceSettings")

    var body: some View {
        ZStack {
            // Liquid Glass background
            LiquidGlass()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .glassEffect(
                            .regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 8))
                    Text("Interface Settings")
                        .font(.largeTitle.bold())
                }
                .padding(.bottom, 8)

                GlassEffectContainer(spacing: 24) {
                    // Card 1: Mouth Import Defaults
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Mouth Import", systemImage: "waveform.path")
                            .font(.headline)
                        #if os(tvOS)
                            HStack {
                                Text("Default Axis")
                                Spacer()
                                TextField("0–15", text: $tvDefaultMouthAxisText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val = Int(tvDefaultMouthAxisText) ?? defaultMouthAxis
                                        let clamped = min(15, max(0, val))
                                        defaultMouthAxis = clamped
                                        tvDefaultMouthAxisText = String(clamped)
                                    }
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #else
                            HStack {
                                Text("Default Axis")
                                Spacer()
                                Stepper(
                                    value: Binding<Double>(
                                        get: { Double(defaultMouthAxis) },
                                        set: { defaultMouthAxis = Int($0) }
                                    ), in: 0...15, step: 1
                                ) {
                                    Text("Axis \(defaultMouthAxis)")
                                }
                                .frame(maxWidth: 180)
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #endif
                    }

                    // Card 2: Server Logs
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Server Logs", systemImage: "text.alignleft")
                            .font(.headline)
                        #if os(tvOS)
                            HStack {
                                Text("Scrollback Lines")
                                Spacer()
                                TextField("10–200", text: $tvServerLogsScrollbackText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val =
                                            Int(tvServerLogsScrollbackText)
                                            ?? serverLogsScrollBackLines
                                        let clamped = min(200, max(10, val))
                                        let snapped = Int((Double(clamped) / 10.0).rounded()) * 10
                                        serverLogsScrollBackLines = snapped
                                        tvServerLogsScrollbackText = String(snapped)
                                    }
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #else
                            HStack {
                                Text("Scrollback Lines")
                                Spacer()
                                Slider(
                                    value: Binding<Double>(
                                        get: { Double(serverLogsScrollBackLines) },
                                        set: { serverLogsScrollBackLines = Int($0) }
                                    ), in: 10...200, step: 10
                                )
                                .frame(maxWidth: 280)
                                Text("\(serverLogsScrollBackLines)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #endif
                    }

                    // Card 3: Audio
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Audio", systemImage: "speaker.wave.2.fill")
                            .font(.headline)
                        #if os(tvOS)
                            HStack {
                                Text("Preview/Playback Volume")
                                Spacer()
                                TextField("0.0–1.0", text: $tvAudioVolumeText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val = Double(tvAudioVolumeText) ?? audioVolume
                                        let clamped = min(1.0, max(0.0, val))
                                        audioVolume = clamped
                                        tvAudioVolumeText = String(format: "%.2f", clamped)
                                    }
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #else
                            HStack {
                                Text("Preview/Playback Volume")
                                Spacer()
                                Slider(
                                    value: $audioVolume,
                                    in: 0.0...1.0,
                                    step: 0.01
                                )
                                .frame(maxWidth: 280)
                                Text(String(format: "%.0f%%", audioVolume * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        #endif
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            #if os(tvOS)
                .onAppear {
                    tvDefaultMouthAxisText = String(defaultMouthAxis)
                    tvServerLogsScrollbackText = String(serverLogsScrollBackLines)
                    tvAudioVolumeText = String(format: "%.2f", audioVolume)
                }
            #endif
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
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .blendMode(.screen)
            )
    }
}
