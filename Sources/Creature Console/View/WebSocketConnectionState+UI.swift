import Common
import SwiftUI

extension WebSocketConnectionState {
    var symbolName: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .connecting:
            return "wifi.exclamationmark"
        case .connected:
            return "wifi"
        case .reconnecting:
            return "arrow.clockwise"
        case .closing:
            return "xmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .disconnected:
            return .red
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .reconnecting:
            return .yellow
        case .closing:
            return .gray
        }
    }
}
