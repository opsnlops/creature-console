import Common
import Foundation
import SwiftUI

struct BottomToolBarView: View {

    @State private var frameSpareTime: Double = 0.0
    @ObservedObject var serverCounters = SystemCountersStore.shared
    @State private var statusLightsState = StatusLightsState(running: false, dmx: false, streaming: false, animationPlaying: false)
    @State private var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )
    @State private var showingSystemAlert = false
    @State private var systemAlertMessage = ""

    var body: some View {

        HStack {
            VStack {
                HStack {
                    Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
                    Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
                    Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
                    Text("Spare Time: \(String(format: "%.2f", frameSpareTime))%")
                }
                HStack {
                    Text("State: \(appState.currentActivity.description)")
                        .font(.footnote)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                StatusIndicator(
                    systemName: "arrow.circlepath", isActive: statusLightsState.running,
                    help: "Server Running")
                StatusIndicator(
                    systemName: "rainbow", isActive: statusLightsState.streaming, help: "Streaming")
                StatusIndicator(
                    systemName: "antenna.radiowaves.left.and.right.circle.fill",
                    isActive: statusLightsState.dmx, help: "DMX Signal")
                StatusIndicator(
                    systemName: "figure.socialdance", isActive: statusLightsState.animationPlaying,
                    help: "Animation Playing")
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.09), radius: 8, y: 2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))

        }
        .padding()
        .alert(isPresented: $showingSystemAlert) {
            Alert(
                title: Text("Server Message"),
                message: Text("The server wants us to know: \(systemAlertMessage)"),
                dismissButton: .default(Text("Okay 😅")) {
                    Task {
                        await AppState.shared.setSystemAlert(show: false)
                    }
                }
            )
        }
        .task {
            // Update frameSpareTime from EventLoop actor
            while !Task.isCancelled {
                frameSpareTime = await EventLoop.shared.frameSpareTime
                try? await Task.sleep(for: .seconds(1)) // Update once per second
            }
        }
        .task {
            for await state in await StatusLightsManager.shared.stateUpdates {
                await MainActor.run {
                    statusLightsState = state
                }
            }
        }
        .task {
            for await state in await AppState.shared.stateUpdates {
                await MainActor.run {
                    appState = state
                    showingSystemAlert = state.showSystemAlert
                    systemAlertMessage = state.systemAlertMessage
                }
            }
        }

    }
}

private struct StatusIndicator: View {
    let systemName: String
    let isActive: Bool
    let help: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(isActive ? .accent : .secondary)
            .padding(8)
            .background(
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .help(help)
    }
}
