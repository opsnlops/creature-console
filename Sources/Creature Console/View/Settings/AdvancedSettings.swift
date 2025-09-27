import Common
import Foundation
import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage("eventLoopMillisecondsPerFrame") private var eventLoopMillisecondsPerFrame: Int = 20
    @AppStorage("logSpareTimeFrameInterval") private var logSpareTimeFrameInterval: Int = 200
    @AppStorage("updateSpareTimeStatusInterval") var updateSpareTimeStatusInterval: Int = 20
    @AppStorage("logSpareTime") private var logSpareTime: Bool = false

    #if os(tvOS)
        @State private var tvEventLoopMsText: String = ""
        @State private var tvUpdateSpareTimeText: String = ""
        @State private var tvLogSpareTimeIntervalText: String = ""
    #endif

    private let trailingControlWidth: CGFloat = 160

    var body: some View {
        ZStack {
            LiquidGlass()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .glassEffect(
                            .regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 8))
                    Text("Advanced Settings")
                        .font(.largeTitle.bold())
                }
                .padding(.bottom, 8)

                GlassEffectContainer(spacing: 24) {
                    // Warning card
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Changing any of these values requires an app restart")
                            .font(.callout)
                    }
                    .padding(12)
                    .glassEffect(.regular.tint(.yellow.opacity(0.35)), in: .rect(cornerRadius: 12))

                    // Card: Timing
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Timing", systemImage: "timer")
                            .font(.headline)
                        HStack {
                            Text("Milliseconds Per Frame")
                            Spacer()
                            #if os(tvOS)
                                TextField("1–100", text: $tvEventLoopMsText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: trailingControlWidth)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val =
                                            Int(tvEventLoopMsText) ?? eventLoopMillisecondsPerFrame
                                        let clamped = min(100, max(1, val))
                                        eventLoopMillisecondsPerFrame = clamped
                                        tvEventLoopMsText = String(clamped)
                                    }
                            #else
                                HStack(spacing: 8) {
                                    Text("\(eventLoopMillisecondsPerFrame) ms")
                                        .monospacedDigit()
                                        .frame(width: 70, alignment: .trailing)
                                    Stepper(
                                        "",
                                        value: Binding<Double>(
                                            get: { Double(eventLoopMillisecondsPerFrame) },
                                            set: { eventLoopMillisecondsPerFrame = Int($0) }
                                        ), in: 1...100, step: 1
                                    )
                                    .labelsHidden()
                                }
                                .frame(width: trailingControlWidth, alignment: .trailing)
                            #endif
                        }
                        HStack {
                            Text("Status Bar Spare Time Update Interval")
                            Spacer()
                            #if os(tvOS)
                                TextField("1–1000", text: $tvUpdateSpareTimeText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: trailingControlWidth)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val =
                                            Int(tvUpdateSpareTimeText)
                                            ?? updateSpareTimeStatusInterval
                                        let clamped = min(1000, max(1, val))
                                        updateSpareTimeStatusInterval = clamped
                                        tvUpdateSpareTimeText = String(clamped)
                                    }
                            #else
                                HStack(spacing: 8) {
                                    Text("\(updateSpareTimeStatusInterval) ms")
                                        .monospacedDigit()
                                        .frame(width: 70, alignment: .trailing)
                                    Stepper(
                                        "",
                                        value: Binding<Double>(
                                            get: { Double(updateSpareTimeStatusInterval) },
                                            set: { updateSpareTimeStatusInterval = Int($0) }
                                        ), in: 1...1000, step: 1
                                    )
                                    .labelsHidden()
                                }
                                .frame(width: trailingControlWidth, alignment: .trailing)
                            #endif
                        }
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                    // Card: Logging
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Logging", systemImage: "text.alignleft")
                            .font(.headline)
                        HStack {
                            Text("Log Spare Time")
                            Spacer()
                            HStack { Toggle("", isOn: $logSpareTime).labelsHidden() }
                                .frame(width: trailingControlWidth, alignment: .trailing)
                        }
                        HStack {
                            Text("Log Spare Time Frame Interval")
                            Spacer()
                            #if os(tvOS)
                                TextField("10–5000", text: $tvLogSpareTimeIntervalText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: trailingControlWidth)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let val =
                                            Int(tvLogSpareTimeIntervalText)
                                            ?? logSpareTimeFrameInterval
                                        let clamped = min(5000, max(10, val))
                                        logSpareTimeFrameInterval = clamped
                                        tvLogSpareTimeIntervalText = String(clamped)
                                    }
                            #else
                                HStack(spacing: 8) {
                                    Text("\(logSpareTimeFrameInterval) ms")
                                        .monospacedDigit()
                                        .frame(width: 70, alignment: .trailing)
                                    Stepper(
                                        "",
                                        value: Binding<Double>(
                                            get: { Double(logSpareTimeFrameInterval) },
                                            set: { logSpareTimeFrameInterval = Int($0) }
                                        ), in: 10...5000, step: 10
                                    )
                                    .labelsHidden()
                                }
                                .frame(width: trailingControlWidth, alignment: .trailing)
                            #endif
                        }
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            #if os(tvOS)
                .onAppear {
                    tvEventLoopMsText = String(eventLoopMillisecondsPerFrame)
                    tvUpdateSpareTimeText = String(updateSpareTimeStatusInterval)
                    tvLogSpareTimeIntervalText = String(logSpareTimeFrameInterval)
                }
            #endif
        }
    }
}

struct AdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettingsView()
    }
}
