import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

enum DiagnosticReporter {
    private static func isoTimestamp() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private static func appInfo() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var dict: [String: Any] = [:]
        dict["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
        dict["version"] = info["CFBundleShortVersionString"] as? String ?? "unknown"
        dict["build"] = info["CFBundleVersion"] as? String ?? "unknown"
        #if canImport(UIKit)
            let device = UIDevice.current
            dict["device"] = [
                "systemName": device.systemName,
                "systemVersion": device.systemVersion,
                "model": device.model,
            ]
        #else
            let osString = ProcessInfo.processInfo.operatingSystemVersionString
            dict["device"] = [
                "systemName": "macOS",
                "systemVersion": osString,
                "model": "Mac",
            ]
        #endif
        return dict
    }

    private static func settingsSnapshot() -> [String: Any] {
        let ud = UserDefaults.standard
        var dict: [String: Any] = [:]
        dict["serverAddress"] = ud.string(forKey: "serverAddress") ?? ""
        dict["serverPort"] = ud.object(forKey: "serverPort") as? Int ?? 0
        dict["serverUseTLS"] = ud.object(forKey: "serverUseTLS") as? Bool ?? true
        dict["activeUniverse"] = ud.object(forKey: "activeUniverse") as? Int ?? 1
        return dict
    }

    private static func writeJSON(_ object: Any, suggestedName: String) -> URL? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let url = tmp.appendingPathComponent("\(suggestedName)-\(isoTimestamp()).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    private static func writeCountersIfAvailable() -> URL? {
        let counters = SystemCountersStore.shared.systemCounters
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(counters) {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let url = tmp.appendingPathComponent("system-counters-\(isoTimestamp()).json")
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func buildSummaryFile() -> URL? {
        var summary: [String: Any] = [:]
        summary["timestamp"] = isoTimestamp()
        summary["app"] = appInfo()
        summary["settings"] = settingsSnapshot()
        #if canImport(MetricKit)
            let recent = MetricKitManager.shared.listRecentDiagnostics(limit: 10)
            summary["recentDiagnosticFiles"] = recent.map { $0.lastPathComponent }
        #else
            summary["recentDiagnosticFiles"] = []
        #endif
        return writeJSON(summary, suggestedName: "console-summary")
    }

    @MainActor
    private static func collectAttachments() -> [URL] {
        var urls: [URL] = []
        if let summary = buildSummaryFile() { urls.append(summary) }
        if let counters = writeCountersIfAvailable() { urls.append(counters) }
        #if canImport(MetricKit)
            urls.append(contentsOf: MetricKitManager.shared.listRecentDiagnostics(limit: 5))
        #endif
        return urls
    }

    @MainActor
    public static func presentDiagnosticsEmail() {
        let attachments = collectAttachments()
        #if canImport(MetricKit)
            let summaryList = MetricKitManager.shared.latestSummary(limit: 10)
        #else
            let summaryList = "MetricKit not available on this platform."
        #endif
        let subject = "Creature Console Diagnostics"
        let body =
            "Attached are diagnostic files and a summary.\n\nRecent files:\n\n\(summaryList)\n\nThank you!"
        MailComposer.present(subject: subject, body: body, to: [], attachments: attachments)
    }
}
