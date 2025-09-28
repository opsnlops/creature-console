import Foundation
import OSLog
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RootView")
    @Environment(\.openURL) private var openURL
    @State private var showingSystemAlert = false
    @State private var systemAlertMessage = ""
    @State private var websocketErrorMessage: String? = nil

    var body: some View {
        TopContentView()
            .task {
                await AppBootstrapper.shared.startIfNeeded()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    Task {
                        await AppBootstrapper.shared.refreshCachesAfterWake()
                    }
                }
            }
            .task {
                let updates = await AppState.shared.stateUpdates
                for await state in updates {
                    await MainActor.run {
                        showingSystemAlert = state.showSystemAlert
                        systemAlertMessage = state.systemAlertMessage
                    }
                }
            }
            .task {
                let name = Notification.Name("WebSocketDidEncounterError")
                for await note in NotificationCenter.default.notifications(named: name, object: nil)
                {
                    if let message = note.object as? String {
                        websocketErrorMessage = message
                    } else {
                        websocketErrorMessage = "WebSocket error occurred."
                    }
                }
            }
            .alert(isPresented: $showingSystemAlert) {
                Alert(
                    title: Text("Server Message"),
                    message: Text(systemAlertMessage),
                    dismissButton: .default(Text("Okay 😅")) {
                        Task { await AppState.shared.setSystemAlert(show: false) }
                    }
                )
            }
            .alert(
                item: Binding(
                    get: {
                        websocketErrorMessage.map { LocalIdentifiedString(id: UUID(), value: $0) }
                    },
                    set: { newValue in
                        websocketErrorMessage = newValue?.value
                    }
                )
            ) { item in
                #if os(tvOS)
                    // tvOS: No email composer; present a simple OK alert
                    return Alert(
                        title: Text("Connection Issue"),
                        message: Text(item.value),
                        dismissButton: .default(Text("OK")) {
                            websocketErrorMessage = nil
                        }
                    )
                #else
                    return Alert(
                        title: Text("Connection Issue"),
                        message: Text(item.value),
                        primaryButton: .default(Text("Report Issue")) {
                            let subject = "Creature Console Issue Report"
                            let os = ProcessInfo.processInfo.operatingSystemVersionString
                            let appVersion =
                                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                ?? "unknown"
                            let build =
                                Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            let diagSummary = MetricKitManager.shared.latestSummary(limit: 3)
                            let body = """
                                Please describe what you were doing:

                                Error:
                                \(item.value)

                                App Version: \(appVersion) (\(build))
                                OS: \(os)
                                Timestamp: \(timestamp)


                                Diagnostics Summary:
                                \(diagSummary)
                                """
                            MailComposer.present(subject: subject, body: body)
                            websocketErrorMessage = nil
                        },
                        secondaryButton: .cancel(Text("OK")) {
                            websocketErrorMessage = nil
                        }
                    )
                #endif
            }
    }
}

private struct LocalIdentifiedString: Identifiable {
    let id: UUID
    let value: String
}
