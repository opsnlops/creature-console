import Foundation
import SwiftData

/// Single source of truth for every persisted SwiftData model. The app's ModelContainer
/// and the debug "reset local data" flow both build from this list, so adding a new
/// @Model only requires touching this one spot.
enum AppSchema {
    static var modelTypes: [any PersistentModel.Type] {
        [
            SoundModel.self, CreatureModel.self, AnimationMetadataModel.self,
            PlaylistModel.self, PlaylistItemModel.self, ServerLogModel.self,
            DmxFixtureModel.self, DialogScriptModel.self, StoryboardModel.self,
        ]
    }
}

/// Batch-deletes every row of every model type. The store file itself stays in place;
/// the app repopulates from the server afterwards.
@ModelActor
actor SwiftDataStoreWiper {
    func wipeAll() throws {
        for modelType in AppSchema.modelTypes {
            try modelContext.delete(model: modelType)
        }
        try modelContext.save()
    }
}
