import Foundation
import os

#if canImport(MetricKit) && !os(tvOS)
    import MetricKit

    final class MetricKitManager: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        static let shared = MetricKitManager()
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "MetricKitManager",
            category: "MetricKitManager")

        private let diagnosticsDirectoryURL: URL = {
            let fm = FileManager.default
            let appSupportDir = try! fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
            let diagnosticsDir = appSupportDir.appendingPathComponent(
                "Diagnostics", isDirectory: true)
            if !fm.fileExists(atPath: diagnosticsDir.path) {
                do {
                    try fm.createDirectory(
                        at: diagnosticsDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    // Will handle error on usage
                }
            }
            return diagnosticsDir
        }()

        private override init() {
            super.init()
        }

        func start() {
            MXMetricManager.shared.add(self)
            logger.log("MetricKitManager started and subscribed to MXMetricManager.")
        }

        func stop() {
            MXMetricManager.shared.remove(self)
            logger.log("MetricKitManager stopped and unsubscribed from MXMetricManager.")
        }

        func didReceive(_ payloads: [MXMetricPayload]) {
            for payload in payloads {
                do {
                    let jsonData = try payload.jsonRepresentation()
                    try writeData(jsonData, prefix: "metrics")
                    logger.log("Saved metric payload successfully.")
                } catch {
                    logger.error("Failed to save metric payload: \(error.localizedDescription)")
                }
            }
        }

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                do {
                    let jsonData = try payload.jsonRepresentation()
                    try writeData(jsonData, prefix: "diagnostics")
                    logger.log("Saved diagnostic payload successfully.")
                } catch {
                    logger.error("Failed to save diagnostic payload: \(error.localizedDescription)")
                }
            }
        }

        private func writeData(_ data: Data, prefix: String) throws {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
                of: ":", with: "-")
            let filename = "\(prefix)-\(timestamp).json"
            let fileURL = diagnosticsDirectoryURL.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)
        }

        /// Returns a short, human-readable list of the most recent diagnostic/metric files (filenames only, newest first).
        func latestSummary(limit: Int = 10) -> String {
            let files = listRecentDiagnostics(limit: limit)
            guard !files.isEmpty else {
                return "No recent diagnostics or metrics files found."
            }
            let filenames = files.map { $0.lastPathComponent }
            return filenames.joined(separator: "\n")
        }

        /// Lists URLs of recent diagnostic and metric files sorted newest first.
        func listRecentDiagnostics(limit: Int = 10) -> [URL] {
            let fm = FileManager.default
            guard
                let contents = try? fm.contentsOfDirectory(
                    at: diagnosticsDirectoryURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            else {
                return []
            }
            let sorted = contents.sorted {
                let d0 =
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                let d1 =
                    (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                return d0 > d1
            }
            return Array(sorted.prefix(limit))
        }

        /// Loads the contents of the file at URL or returns nil on failure.
        func loadFile(_ url: URL) -> String? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

#else

    final class MetricKitManager: @unchecked Sendable {
        static let shared = MetricKitManager()

        private init() {}

        func start() {
            // No-op: MetricKit not available.
        }

        func stop() {
            // No-op: MetricKit not available.
        }

        func latestSummary(limit: Int = 10) -> String {
            "MetricKit is not available on this platform."
        }

        func listRecentDiagnostics(limit: Int = 10) -> [URL] { [] }

        func loadFile(_ url: URL) -> String? { nil }
    }
#endif
