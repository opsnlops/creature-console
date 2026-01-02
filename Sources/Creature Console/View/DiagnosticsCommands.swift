import SwiftUI

struct DiagnosticsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Diagnostics") {
            Button("Report Issue…") {
                let subject = "Creature Console Issue Report"
                let os = ProcessInfo.processInfo.operatingSystemVersionString
                let appVersion =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "unknown"
                let build =
                    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let diagSummary = MetricKitManager.shared.latestSummary(limit: 5)
                let body = """
                    Please describe what you were doing:

                    App Version: \(appVersion) (\(build))
                    OS: \(os)
                    Timestamp: \(timestamp)


                    Diagnostics Summary:
                    \(diagSummary)
                    """
                MailComposer.present(subject: subject, body: body)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("sACN Universe Monitor…") {
                openWindow(id: "sacnUniverseMonitor")
            }
            Divider()
            Button("Rebuild All Caches...") {
                CacheInvalidationProcessor.rebuildAllCaches()
            }
        }
    }
}
