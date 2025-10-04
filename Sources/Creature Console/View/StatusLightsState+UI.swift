import Common
import SwiftUI

extension StatusLightsState {
    enum Light: Hashable {
        case running
        case dmx
        case streaming
        case animationPlaying

        var symbolName: String {
            switch self {
            case .running:
                return "arrow.circlepath"
            case .dmx:
                return "antenna.radiowaves.left.and.right.circle.fill"
            case .streaming:
                return "arrow.up.arrow.down.circle.fill"
            case .animationPlaying:
                return "figure.socialdance"
            }
        }

        var tintColor: Color {
            switch self {
            case .running:
                return .orange
            case .dmx:
                return .blue
            case .streaming:
                return .pink
            case .animationPlaying:
                return .purple
            }
        }

        var helpText: String {
            switch self {
            case .running:
                return "Server Running"
            case .dmx:
                return "DMX Signal"
            case .streaming:
                return "Streaming"
            case .animationPlaying:
                return "Animation Playing"
            }
        }

        func isActive(in state: StatusLightsState) -> Bool {
            switch self {
            case .running:
                return state.running
            case .dmx:
                return state.dmx
            case .streaming:
                return state.streaming
            case .animationPlaying:
                return state.animationPlaying
            }
        }
    }

    static let allLights: [Light] = [.running, .streaming, .dmx, .animationPlaying]
}
