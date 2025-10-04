import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

extension CreatureManager {


    func populateCache() async -> Result<String, ServerError> {

        logger.info("(re)populating the Creature SwiftData cache")

        let creatureList = await server.getAllCreatures()
        switch creatureList {
        case .success(let list):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = CreatureImporter(modelContainer: container)
                try await importer.upsertBatch(list)
                logger.debug("(re)populated the SwiftData cache with \(list.count) creatures")
                return .success("Successfully populated the cache with \(list.count) creatures!")
            } catch {
                logger.warning(
                    "Unable to import creatures into SwiftData: \(error.localizedDescription)")
                return .failure(
                    .databaseError("SwiftData import failed: \(error.localizedDescription)"))
            }
        case .failure(let error):
            logger.warning(
                "Unable to (re)populate the creature cache: \(error.localizedDescription)")
            return .failure(error)
        }
    }


}
