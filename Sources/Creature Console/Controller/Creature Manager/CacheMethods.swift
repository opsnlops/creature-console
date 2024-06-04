
import Common
import Foundation
import OSLog
import SwiftUI



extension CreatureManager {


    func populateCache() async -> Result<String, ServerError> {

        logger.info("(re)populating the CreatureCache")

        let creatureList = await server.getAllCreatures()
        switch(creatureList) {
        case .success(let list):
            creatureCache.reload(with: list)
            logger.debug("(re)populated the cache")
        case .failure(let error):
            logger.warning("Unable to (re)populate the creature cache: \(error.localizedDescription)")
            return .failure(error)
        }

        return .success("Successfully populated the cache with \(creatureCache.creatures.count) creatures!")
    }


}
