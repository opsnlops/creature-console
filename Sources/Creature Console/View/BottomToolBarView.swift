import Common
import Foundation
import SwiftUI

struct BottomToolBarView: View {

    @Environment(ConsoleStore.self) private var console
    @State private var frameSpareTime: Double = 0.0
    private let serverCounters = SystemCountersStore.shared
    @State private var systemAlert: ErrorAlert?
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
                        Image(systemName: console.currentActivity.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(console.currentActivity.description)
                            .font(.footnote)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(
                        .regular
                            .tint(console.currentActivity.tintColor.opacity(0.35))
                            .interactive(),
                        in: .capsule
                    )
                    .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)
                    .animation(.easeInOut(duration: 0.25), value: console.currentActivity)

                    HStack(spacing: 6) {
                        Image(systemName: console.websocketState.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(console.websocketState.description)
                            .font(.footnote)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(
                        .regular
                            .tint(console.websocketState.tintColor.opacity(0.35))
                            .interactive(),
                        in: .capsule
                    )
                    .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)
                    .animation(.easeInOut(duration: 0.25), value: console.websocketState)
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
                            isActive: light.isActive(in: console.statusLights),
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
        .errorAlert($systemAlert, dismissLabel: "Okay 😅") {
            Task {
                await AppState.shared.setSystemAlert(show: false)
            }
        }
        // Present (or clear) the server's system alert whenever the flag flips; `initial: true`
        // covers an alert that was already raised before this view appeared.
        .onChange(of: console.appState.showSystemAlert, initial: true) { _, showAlert in
            systemAlert =
                showAlert
                ? ErrorAlert(
                    title: "Server Message",
                    message:
                        "The server wants us to know: \(console.appState.systemAlertMessage)")
                : nil
        }
        .task {
            // Update frameSpareTime from EventLoop actor
            while !Task.isCancelled {
                frameSpareTime = await EventLoop.shared.frameSpareTime
                try? await Task.sleep(for: .seconds(1))  // Update once per second
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
