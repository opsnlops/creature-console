import Foundation
import Logging

extension CreatureServerClient {

    private func invalidateCache(for type: CacheType) async -> Result<StatusDTO, ServerError> {
        let cacheTypeString: String
        switch type {
        case .animation:
            cacheTypeString = "animation"
        case .creature:
            cacheTypeString = "creature"
        case .playlist:
            cacheTypeString = "playlist"
        case .soundList:
            cacheTypeString = "sound-list"
        case .adHocAnimationList:
            cacheTypeString = "ad-hoc-animation-list"
        case .adHocSoundList:
            cacheTypeString = "ad-hoc-sound-list"
        case .fixture:
            cacheTypeString = "fixture"
        case .dialogScriptList:
            cacheTypeString = "dialog-script-list"
        case .storyboardList:
            cacheTypeString = "storyboard-list"
        case .unknown:
            cacheTypeString = "unknown"
        }

        logger.debug("telling the server to send a \(cacheTypeString) cache invalidation message")

        logger.debug("calling fetchData() now...")
        let returnObject = await fetchData(
            path: "/debug/cache-invalidate/\(cacheTypeString)", returnType: StatusDTO.self)
        logger.debug("...and we're back!")

        // Yay we got something back
        switch returnObject {
        case .success(let status):
            logger.info(
                "successfully told the server to send an invalidate message: \(status.message)")
            return .success(status)
        case .failure(let error):
            logger.warning("unable to send an invalidation message: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    public func invalidateCreatureCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .creature)
    }

    public func invalidatePlaylistCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .playlist)
    }

    public func invalidateAnimationCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .animation)
    }

    public func invalidateSoundListCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .soundList)
    }

    public func invalidateFixtureCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .fixture)
    }

    public func invalidateDialogScriptCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .dialogScriptList)
    }

    public func invalidateStoryboardCache() async -> Result<StatusDTO, ServerError> {
        return await invalidateCache(for: .storyboardList)
    }

    public func testPlaylistUpdates() async -> Result<StatusDTO, ServerError> {

        logger.debug("telling the server to send a fake playlist update command")

        logger.debug("calling fetchData() now...")
        let returnObject = await fetchData(path: "/debug/playlist/update", returnType: StatusDTO.self)
        logger.debug("...and we're back!")

        // Yay we got something back
        switch returnObject {
        case .success(let status):
            logger.info(
                "successfully told the server to send a fake playlist update: \(status.message)")
            return .success(status)
        case .failure(let error):
            logger.warning(
                "unable to send a request to send a fake playlist update: \(error.localizedDescription)"
            )
            return .failure(error)
        }
    }
}
