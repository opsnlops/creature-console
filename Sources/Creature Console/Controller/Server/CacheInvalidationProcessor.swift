import Common
import Foundation
import OSLog
import SwiftUI

struct CacheInvalidationProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CacheInvalidationProcessor")

    static func processCacheInvalidation(_ request: CacheInvalidation) {
        switch request.cacheType {
        case .creature:
            rebuildCreatureCache()
        default:
            return

        }
    }


    static func rebuildCreatureCache() {

        logger.info("attempting to rebuild the creature cache")

        let server = CreatureServerClient.shared

        Task {
            logger.debug("calling out to the server now...")
            let creatureRequest = await server.getAllCreatures()
            switch creatureRequest {
            case .success(let creatureList):
                logger.info("got the latest creature list from the server, rebuilding cache now...")
                CreatureCache.shared.reload(with: creatureList)
            case .failure(let error):
                logger.warning(
                    "unable to get a new copy of the creature list: \(error.localizedDescription)")
                AppState.shared.systemAlertMessage =
                    "Unable to reload the creature cache after getting an invalidation message: \(error.localizedDescription)"
                AppState.shared.showSystemAlert = true
            }
        }

    }
}
