import Common
import SwiftUI

struct BottomStatusToolbarContent: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var statusLightsState = StatusLightsState(
        running: false, dmx: false, streaming: false, animationPlaying: false)
    @State private var currentActivity: Activity = .idle
    @State private var websocketState: WebSocketConnectionState = .disconnected
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Current activity indicator
                ToolbarStatusDot(
                    systemName: currentActivity.symbolName,
                    active: currentActivity != .idle,
                    tint: currentActivity.tintColor,
                    namespace: glassNamespace,
                    unionID: "activityStatus"
                )

                // WebSocket status indicator
                ToolbarStatusDot(
                    systemName: websocketState.symbolName,
                    active: websocketState == .connected,
                    tint: websocketState.tintColor,
                    namespace: glassNamespace,
                    unionID: "websocketStatus"
                )

                // Cluster of status lights
                HStack(spacing: 10) {
                    ForEach(StatusLightsState.allLights, id: \.self) { light in
                        ToolbarStatusDot(
                            systemName: light.symbolName,
                            active: light.isActive(in: statusLightsState),
                            tint: light.tintColor,
                            namespace: glassNamespace,
                            unionID: "statusLights"
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .task {
            // Listen for status light updates
            for await state in await StatusLightsManager.shared.stateUpdates {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    statusLightsState = state
                }
            }
        }
        .task { @MainActor in
            // Get initial state immediately
            let initialActivity = await AppState.shared.getCurrentActivity
            currentActivity = initialActivity

            // Then subscribe to updates with proper cancellation checking
            for await state in await AppState.shared.stateUpdates {
                guard !Task.isCancelled else { break }
                currentActivity = state.currentActivity
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

private struct ToolbarStatusDot: View {
    let systemName: String
    let active: Bool
    let tint: Color
    let namespace: Namespace.ID
    let unionID: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle(active ? .white : .secondary)
            .padding(8)
            .glassEffect(
                .regular
                    .tint(tint.opacity(active ? 0.85 : 0.25))
                    .interactive(),
                in: .circle
            )
            .glassEffectUnion(id: "\(unionID)-\(systemName)", namespace: namespace)
            .scaleEffect(active ? 1.06 : 1.0)
            .opacity(active ? 1.0 : 0.85)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: active)
    }
}
