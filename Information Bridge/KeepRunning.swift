import Foundation
import ServiceManagement

/// The Bridge is meant to run unattended: at login, and back within seconds if it ever dies.
/// Both come from one LaunchAgent inside the bundle (`KeepAlive`, `RunAtLoad`) that
/// `SMAppService` registers for the user - macOS shows it under Login Items, where April can
/// turn it off as well.
@MainActor
enum KeepRunning {
    static let agentPlist = "io.opsnlops.Information-Bridge.agent.plist"

    private static var service: SMAppService { .agent(plistName: agentPlist) }

    /// Whether launchd has the Bridge: registered and allowed.
    static var isOn: Bool { service.status == .enabled }

    /// What macOS says, for the settings line: "on", "off", "needs approval in Login Items".
    static var statusText: String {
        switch service.status {
        case .enabled: "on - launchd starts the Bridge at login and brings it back if it stops"
        case .requiresApproval: "waiting for approval in System Settings → General → Login Items"
        case .notRegistered: "off"
        case .notFound: "the launch agent is missing from the app bundle"
        @unknown default: "unknown"
        }
    }

    static func turnOn() throws {
        try service.register()
    }

    static func turnOff() throws {
        try service.unregister()
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
