import Common
import SwiftUI

struct BottomStatusToolbarContent: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var statusLightsState = StatusLightsState(
        running: false, dmx: false, streaming: false, animationPlaying: false)
    @State private var currentActivity: Activity = .idle
    @Namespace private var glassNamespace

    var body: some View {
        HStack(spacing: 12) {
            // State chip (compact = dot)
            if hSize == .regular {
                HStack(spacing: 6) {
                    Image(systemName: symbolForActivity(currentActivity))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("State: \(currentActivity.description)")
                        .font(.footnote)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(
                    .regular
                        .tint(currentActivity.tintColor.opacity(0.35))
                        .interactive(),
                    in: .capsule
                )
                .animation(.easeInOut(duration: 0.25), value: currentActivity)
            } else {
                Image(systemName: symbolForActivity(currentActivity))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(8)
                    .glassEffect(
                        .regular
                            .tint(currentActivity.tintColor.opacity(0.6))
                            .interactive(),
                        in: .circle
                    )
                    .animation(.easeInOut(duration: 0.25), value: currentActivity)
            }

            // Cluster of status lights
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 10) {
                    ToolbarStatusDot(
                        systemName: "arrow.circlepath",
                        active: statusLightsState.running,
                        tint: .green,
                        namespace: glassNamespace
                    )
                    ToolbarStatusDot(
                        systemName: "rainbow",
                        active: statusLightsState.streaming,
                        tint: .teal,
                        namespace: glassNamespace
                    )
                    ToolbarStatusDot(
                        systemName: "antenna.radiowaves.left.and.right.circle.fill",
                        active: statusLightsState.dmx,
                        tint: .blue,
                        namespace: glassNamespace
                    )
                    ToolbarStatusDot(
                        systemName: "figure.socialdance",
                        active: statusLightsState.animationPlaying,
                        tint: .purple,
                        namespace: glassNamespace
                    )
                }
            }
        }
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
            do {
                // Get initial state immediately
                let initialActivity = await AppState.shared.getCurrentActivity
                currentActivity = initialActivity

                // Then subscribe to updates with proper cancellation checking
                for await state in await AppState.shared.stateUpdates {
                    guard !Task.isCancelled else { break }
                    currentActivity = state.currentActivity
                }
            } catch {
                // Handle any errors gracefully
            }
        }
    }
}

private func symbolForActivity(_ activity: Activity) -> String {
    switch activity {
    case .idle:
        return "pause.circle.fill"
    case .streaming:
        return "dot.radiowaves.left.and.right"
    case .recording:
        return "record.circle.fill"
    case .preparingToRecord:
        return "timer"
    case .playingAnimation:
        return "figure.socialdance"
    case .connectingToServer:
        return "arrow.triangle.2.circlepath.circle"
    }
}

private struct ToolbarStatusDot: View {
    let systemName: String
    let active: Bool
    let tint: Color
    let namespace: Namespace.ID

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? .white : .secondary)
            .padding(8)
            .glassEffect(
                .regular
                    .tint(tint.opacity(active ? 0.85 : 0.25))
                    .interactive(),
                in: .circle
            )
            .glassEffectUnion(id: "statusLights", namespace: namespace)
            .scaleEffect(active ? 1.06 : 1.0)
            .opacity(active ? 1.0 : 0.85)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: active)
    }
}
