import Foundation
import OSLog
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RootView")
    @Environment(\.openURL) private var openURL
    @State private var showingSystemAlert = false
    @State private var systemAlertMessage = ""
    @State private var websocketErrorMessage: String? = nil

    @ViewBuilder
    private var contentView: some View {
        TopContentView()
            .task {
                await AppBootstrapper.shared.startIfNeeded()
            }
    }

    var body: some View {
        contentView
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
                    showingSystemAlert = state.showSystemAlert
                    systemAlertMessage = state.systemAlertMessage
                }
            }
            .task {
                let name = Notification.Name("WebSocketDidEncounterError")
                for await note in NotificationCenter.default.notifications(named: name, object: nil)
                {
                    websocketErrorMessage = (note.object as? String) ?? "WebSocket error occurred."
                }
            }
            .alert("Server Message", isPresented: $showingSystemAlert) {
                Button("Okay 😅") {
                    Task { await AppState.shared.setSystemAlert(show: false) }
                }
            } message: {
                Text(systemAlertMessage)
            }
            .alert(
                "Connection Issue",
                isPresented: Binding(
                    get: { websocketErrorMessage != nil },
                    set: { presented in if !presented { websocketErrorMessage = nil } }
                ),
                presenting: websocketErrorMessage
            ) { message in
                // tvOS has no email composer; it gets just the OK button
                #if !os(tvOS)
                    Button("Report Issue") {
                        reportConnectionIssue(message)
                    }
                #endif
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    #if !os(tvOS)
        private func reportConnectionIssue(_ message: String) {
            let subject = "Creature Console Issue Report"
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            let appVersion =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                ?? "unknown"
            let build =
                Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                ?? "unknown"
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let diagSummary = MetricKitManager.shared.latestSummary(limit: 3)
            let body = """
                Please describe what you were doing:

                Error:
                \(message)

                App Version: \(appVersion) (\(build))
                OS: \(os)
                Timestamp: \(timestamp)


                Diagnostics Summary:
                \(diagSummary)
                """
            MailComposer.present(subject: subject, body: body)
        }
    #endif
}
