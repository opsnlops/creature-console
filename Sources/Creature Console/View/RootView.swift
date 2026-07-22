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
    @Environment(ConsoleStore.self) private var console
    // Local mirror of the server's system-alert flag: `.alert(isPresented:)` needs a mutable
    // Binding it can flip to false immediately on dismissal, before the round trip through
    // AppState (setSystemAlert → stream → ConsoleStore) lands.
    @State private var showingSystemAlert = false
    @State private var websocketErrorMessage: String? = nil
    #if os(macOS)
        @State private var otherInstance: DuplicateInstanceGuard.OtherInstance? = nil
    #endif

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
            // `initial: true` picks up an alert that was already raised before this view appeared.
            .onChange(of: console.appState.showSystemAlert, initial: true) { _, showAlert in
                showingSystemAlert = showAlert
            }
            #if os(macOS)
                // A second running copy double-imports every server message into the shared
                // SwiftData store (issue #47) — surface it before the damage accumulates.
                .onAppear {
                    otherInstance = DuplicateInstanceGuard.findOtherInstance()
                }
                .alert(
                    "Another Copy Is Running",
                    isPresented: Binding(
                        get: { otherInstance != nil },
                        set: { presented in if !presented { otherInstance = nil } }
                    ),
                    presenting: otherInstance
                ) { instance in
                    Button("Quit Other Copy") {
                        DuplicateInstanceGuard.quit(instance)
                    }
                    Button("Ignore", role: .cancel) {}
                } message: { instance in
                    Text(
                        """
                        \(instance.summary) is already running. Two copies both import \
                        server data into the same local store, doubling everything.
                        """)
                }
            #endif
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
                Text(console.appState.systemAlertMessage)
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
