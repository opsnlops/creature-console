import Common
import Foundation

struct VirtualStatusLightsProcessor {

    public static func processVirtualStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        Task {
            await StatusLightsManager.shared.update(from: statusLights)
        }
    }
}
