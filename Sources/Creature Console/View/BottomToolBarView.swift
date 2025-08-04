import Common
import Foundation
import SwiftUI

struct BottomToolBarView: View {

    @ObservedObject var eventLoop = EventLoop.shared
    @ObservedObject var serverCounters = SystemCountersStore.shared
    @ObservedObject var statusLights = StatusLightsManager.shared
    @StateObject var appState = AppState.shared

    var body: some View {

        HStack {
            VStack {
                HStack {
                    Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
                    Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
                    Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
                    Text("Spare Time: \(String(format: "%.2f", eventLoop.frameSpareTime))%")
                }
                HStack {
                    Text("State: \(appState.currentActivity)")
                        .font(.footnote)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                StatusIndicator(
                    systemName: "arrow.circlepath", isActive: statusLights.running,
                    help: "Server Running")
                StatusIndicator(
                    systemName: "rainbow", isActive: statusLights.streaming, help: "Streaming")
                StatusIndicator(
                    systemName: "antenna.radiowaves.left.and.right.circle.fill",
                    isActive: statusLights.dmx, help: "DMX Signal")
                StatusIndicator(
                    systemName: "figure.socialdance", isActive: statusLights.animationPlaying,
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
        .alert(isPresented: $appState.showSystemAlert) {
            Alert(
                title: Text("Server Message"),
                message: Text("The server wants us to know: \(appState.systemAlertMessage)"),
                dismissButton: .default(Text("Okay 😅"))
            )
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
