import Common
import SwiftUI

struct BottomStatusToolbarContent: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(ConsoleStore.self) private var console
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Current activity indicator
                ToolbarStatusDot(
                    systemName: console.currentActivity.symbolName,
                    active: console.currentActivity != .idle,
                    tint: console.currentActivity.tintColor,
                    namespace: glassNamespace,
                    unionID: "activityStatus"
                )

                // WebSocket status indicator
                ToolbarStatusDot(
                    systemName: console.websocketState.symbolName,
                    active: console.websocketState == .connected,
                    tint: console.websocketState.tintColor,
                    namespace: glassNamespace,
                    unionID: "websocketStatus"
                )

                // Cluster of status lights
                HStack(spacing: 10) {
                    ForEach(StatusLightsState.allLights, id: \.self) { light in
                        ToolbarStatusDot(
                            systemName: light.symbolName,
                            active: light.isActive(in: console.statusLights),
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
