import Common
import Foundation
import SwiftUI

struct BottomToolBarView: View {

    @State private var frameSpareTime: Double = 0.0
    @ObservedObject var serverCounters = SystemCountersStore.shared
    @State private var statusLightsState = StatusLightsState(
        running: false, dmx: false, streaming: false, animationPlaying: false)
    @State private var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )
    @State private var websocketState: WebSocketConnectionState = .disconnected
    @State private var showingSystemAlert = false
    @State private var systemAlertMessage = ""
    @Namespace private var glassNamespace

    var body: some View {

        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
                    Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
                    Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
                    Text("Spare Time: \(String(format: "%.2f", frameSpareTime))%")
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.currentActivity.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(appState.currentActivity.description)
                            .font(.footnote)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(
                        .regular
                            .tint(appState.currentActivity.tintColor.opacity(0.35))
                            .interactive(),
                        in: .capsule
                    )
                    .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)
                    .animation(.easeInOut(duration: 0.25), value: appState.currentActivity)

                    HStack(spacing: 6) {
                        Image(systemName: websocketState.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(websocketState.description)
                            .font(.footnote)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(
                        .regular
                            .tint(websocketState.tintColor.opacity(0.35))
                            .interactive(),
                        in: .capsule
                    )
                    .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)
                    .animation(.easeInOut(duration: 0.25), value: websocketState)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            .glassEffectUnion(id: "bottomToolbar", namespace: glassNamespace)

            Spacer()

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(StatusLightsState.allLights, id: \.self) { light in
                        StatusIndicator(
                            systemName: light.symbolName,
                            isActive: light.isActive(in: statusLightsState),
                            help: light.helpText,
                            tint: light.tintColor,
                            namespace: glassNamespace,
                            unionGroup: "statusLights"
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

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
                try? await Task.sleep(for: .seconds(1))  // Update once per second
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
        .task { @MainActor in
            // Get initial websocket state
            let initialWebSocketState = await WebSocketStateManager.shared.getCurrentState
            websocketState = initialWebSocketState

            // Subscribe to websocket state updates
            for await state in await WebSocketStateManager.shared.stateUpdates {
                guard !Task.isCancelled else { break }
                websocketState = state
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
            .glassEffectUnion(id: "\(unionGroup)-\(systemName)", namespace: namespace)
            .scaleEffect(isActive ? 1.06 : 1.0)
            .opacity(isActive ? 1.0 : 0.8)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
            .help(help)
    }
}
