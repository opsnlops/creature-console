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
            StageModel.self,
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

/// One-time carryover of legacy relay preference keys to the unified names. The sACN and
/// audio monitors grew up separately ("sacnRemoteHost"/"spatialRelayHost", "Remote" vs
/// "Relay") — everything now shares "relayHost" and per-service "…RelayPort" keys (#72).
enum PreferenceMigration {
    static func migrateRelayKeys() {
        let defaults = UserDefaults.standard
        let renames = [
            ("sacnRemoteHost", "relayHost"),
            ("spatialRelayHost", "relayHost"),
            ("sacnRemotePort", "sacnRelayPort"),
            ("spatialRelayPort", "audioRelayPort"),
        ]
        for (legacy, unified) in renames {
            let persisted =
                defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            if let value = persisted[legacy] {
                let emptyString = (value as? String)?.isEmpty ?? false
                if persisted[unified] == nil, !emptyString {
                    defaults.set(value, forKey: unified)
                }
                defaults.removeObject(forKey: legacy)
            }
        }
    }
}
