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
    @Namespace private var glassNamespace

    private func activityTint(for activity: Activity) -> Color {
        switch activity {
        case .idle:               return .blue
        case .streaming:          return .green
        case .recording:          return .red
        case .preparingToRecord:  return .yellow
        case .playingAnimation:   return .purple
        case .connectingToServer: return .pink
        }
    }

    var body: some View {

        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
                    Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
                    Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
                    Text("Spare Time: \(String(format: "%.2f", frameSpareTime))%")
                }
                HStack {
                    Text("State: \(appState.currentActivity.description)")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(
                            .regular
                                .tint(activityTint(for: appState.currentActivity).opacity(0.35))
                                .interactive(),
                            in: .capsule
                        )
                        .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)
                        .animation(.easeInOut(duration: 0.25), value: appState.currentActivity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            .glassEffectUnion(id: "bottomToolbar", namespace: glassNamespace)

            Spacer()

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 10) {
                    StatusIndicator(
                        systemName: "arrow.circlepath",
                        isActive: statusLightsState.running,
                        help: "Server Running",
                        tint: .green,
                        namespace: glassNamespace,
                        unionGroup: "statusCluster"
                    )
                    StatusIndicator(
                        systemName: "rainbow",
                        isActive: statusLightsState.streaming,
                        help: "Streaming",
                        tint: .teal,
                        namespace: glassNamespace,
                        unionGroup: "statusCluster"
                    )
                    StatusIndicator(
                        systemName: "antenna.radiowaves.left.and.right.circle.fill",
                        isActive: statusLightsState.dmx,
                        help: "DMX Signal",
                        tint: .blue,
                        namespace: glassNamespace,
                        unionGroup: "statusCluster"
                    )
                    StatusIndicator(
                        systemName: "figure.socialdance",
                        isActive: statusLightsState.animationPlaying,
                        help: "Animation Playing",
                        tint: .purple,
                        namespace: glassNamespace,
                        unionGroup: "statusCluster"
                    )
                }
            }
            .padding(.horizontal, 4)

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
        .task { @MainActor in
            // Seed with the current activity so the UI reflects the latest state immediately
            let initialActivity = await AppState.shared.getCurrentActivity
            appState = AppStateData(
                currentActivity: initialActivity,
                currentAnimation: appState.currentAnimation,
                selectedTrack: appState.selectedTrack,
                showSystemAlert: appState.showSystemAlert,
                systemAlertMessage: appState.systemAlertMessage
            )

            // Capture the async sequence once, then iterate on the main actor to avoid dropping updates
            let updates = await AppState.shared.stateUpdates
            for await state in updates {
                appState = state
                showingSystemAlert = state.showSystemAlert
                systemAlertMessage = state.systemAlertMessage
            }
        }

    }
}

private struct StatusIndicator: View {
    let systemName: String
    let isActive: Bool
    let help: String
    let tint: Color
    let namespace: Namespace.ID
    let unionGroup: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(10)
            .glassEffect(
                .regular
                    .tint(tint.opacity(isActive ? 0.85 : 0.25))
                    .interactive(),
                in: .circle
            )
            .glassEffectUnion(id: unionGroup, namespace: namespace)
            .scaleEffect(isActive ? 1.06 : 1.0)
            .opacity(isActive ? 1.0 : 0.8)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
            .help(help)
    }
}
