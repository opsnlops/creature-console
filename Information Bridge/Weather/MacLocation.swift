import CoreLocation
import Foundation

/// Where this Mac is, asked once: the house is wherever the Bridge's Mac lives. macOS asks April
/// for permission the first time; a Mac with Location Services off yields nothing, and the
/// Bridge says so instead of guessing.
enum MacLocation {
    struct Fix: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var accuracyMeters: Double
    }

    enum Failure: Error, CustomStringConvertible {
        case denied
        case unavailable

        var description: String {
            switch self {
            case .denied:
                "Location Services are off for Information Bridge (System Settings → Privacy & Security → Location Services)"
            case .unavailable: "This Mac could not work out where it is"
            }
        }
    }

    /// The first good fix, or a reason there is none. Waits at most `timeout`.
    static func fix(timeout: Duration = .seconds(20)) async throws -> Fix {
        try await withThrowingTaskGroup(of: Fix.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        throw Failure.denied
                    }
                    if update.locationUnavailable { throw Failure.unavailable }
                    if let location = update.location {
                        return Fix(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            accuracyMeters: location.horizontalAccuracy)
                    }
                }
                throw Failure.unavailable
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.unavailable
            }
            guard let fix = try await group.next() else { throw Failure.unavailable }
            group.cancelAll()
            return fix
        }
    }
}
