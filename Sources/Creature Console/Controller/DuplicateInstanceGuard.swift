import Foundation

#if os(macOS)
    import AppKit

    /// Detects another running copy of Creature Console (issue #47).
    ///
    /// macOS only prevents double-launching the *same bundle path*, so an installed copy in
    /// /Applications and a DerivedData dev build run concurrently without complaint — and the
    /// menu-bar extra keeps an instance alive with zero visible windows. Two instances both
    /// import every server message into the shared SwiftData store, silently doubling all
    /// server data (issue #45 was three days of this). This guard turns that silent corruption
    /// into a one-click fix at launch.
    @MainActor
    enum DuplicateInstanceGuard {

        struct OtherInstance {
            let app: NSRunningApplication
            let path: String
            let version: String

            /// Human-readable line for the warning alert.
            var summary: String {
                "Version \(version) at \(path)"
            }
        }

        /// The other running copy of this app, if one exists.
        static func findOtherInstance() -> OtherInstance? {
            guard let bundleId = Bundle.main.bundleIdentifier else { return nil }

            let ourPid = ProcessInfo.processInfo.processIdentifier
            guard
                let other = NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleId
                ).first(where: { $0.processIdentifier != ourPid })
            else { return nil }

            let path = other.bundleURL?.path ?? "unknown location"
            let version =
                other.bundleURL.flatMap { Bundle(url: $0) }?
                .infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

            return OtherInstance(app: other, path: path, version: version)
        }

        /// Ask the other copy to quit. Returns whether the request was delivered
        /// (termination itself is asynchronous).
        @discardableResult
        static func quit(_ instance: OtherInstance) -> Bool {
            instance.app.terminate()
        }
    }
#endif
