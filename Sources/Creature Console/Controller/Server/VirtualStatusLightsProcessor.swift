import Common
import Foundation

struct VirtualStatusLightsProcessor {

    public static func processVirtualStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        StatusLightsManager.shared.update(from: statusLights)
    }
}
