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
        case denied(CLAuthorizationStatus)
        case unavailable
        case unanswered

        var description: String {
            switch self {
            case .denied(let status):
                "Location Services are off for Information Bridge (System Settings → Privacy & Security → Location Services); status \(status.rawValue)"
            case .unavailable: "This Mac could not work out where it is"
            case .unanswered:
                "macOS never asked whether the Bridge may know where this Mac is (is Location Services on in System Settings → Privacy & Security?)"
            }
        }
    }

    /// The first good fix, or a reason there is none. Waits at most `timeout`. Live updates
    /// alone never prompt on macOS; the manager asks, and the answer is awaited first.
    static func fix(timeout: Duration = .seconds(60)) async throws -> Fix {
        let status = try await withThrowingTaskGroup(of: CLAuthorizationStatus.self) { group in
            group.addTask { await Authorizer().authorize() }
            group.addTask {
                try await Task.sleep(for: .seconds(90))
                throw Failure.unanswered
            }
            guard let status = try await group.next() else { throw Failure.unanswered }
            group.cancelAll()
            return status
        }
        switch status {
        case .denied, .restricted: throw Failure.denied(status)
        default: break
        }
        return try await withThrowingTaskGroup(of: Fix.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        throw Failure.denied(.denied)
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

    /// Asks macOS, once, on the main thread the manager needs, and waits for the answer.
    @MainActor
    private final class Authorizer: NSObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

        func authorize() async -> CLAuthorizationStatus {
            manager.delegate = self
            let status = manager.authorizationStatus
            guard status == .notDetermined else { return status }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
                // Some macOS releases only put the dialog up once a fix is actually wanted.
                manager.startUpdatingLocation()
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            Task { @MainActor in self.answered() }
        }

        private func answered() {
            let status = manager.authorizationStatus
            guard status != .notDetermined, let continuation else { return }
            manager.stopUpdatingLocation()
            self.continuation = nil
            continuation.resume(returning: status)
        }
    }
}
