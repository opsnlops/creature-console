import Combine
import Common
import Foundation
import OSLog

struct PlaylistCacheState: Sendable {
    let playlists: [PlaylistIdentifier: Playlist]
    let empty: Bool
}

actor PlaylistCache {
    static let shared = PlaylistCache()

    private var playlists: [PlaylistIdentifier: Playlist] = [:]
    private var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistCache")

    // AsyncStream for UI updates
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(
        of: PlaylistCacheState.self)

    var stateUpdates: AsyncStream<PlaylistCacheState> {
        stateStream
    }

    private init() {}

    func addPlaylist(_ playlist: Playlist, for id: PlaylistIdentifier) {
        playlists[id] = playlist
        empty = playlists.isEmpty
        publishState()
    }

    private func publishState() {
        let currentState = PlaylistCacheState(
            playlists: playlists,
            empty: empty
        )
        stateContinuation.yield(currentState)
    }

    func removePlaylist(for id: PlaylistIdentifier) {
        playlists.removeValue(forKey: id)
        empty = playlists.isEmpty
        publishState()
    }

    public func reload(with playlists: [Playlist]) {
        let reloadedPlaylists = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        self.playlists = reloadedPlaylists
        self.empty = reloadedPlaylists.isEmpty
        publishState()
    }

    public func getById(id: PlaylistIdentifier) -> Result<Playlist, ServerError> {
        if let playlist = playlists[id] {
            return .success(playlist)
        } else {
            logger.warning(
                "PlaylistCache.getById() called on an ID that wasn't in the cache! \(id)")
            return .failure(.notFound("Playlist ID \(id) not found in the cache"))
        }
    }

    public func getCurrentState() -> PlaylistCacheState {
        return PlaylistCacheState(playlists: playlists, empty: empty)
    }

    public func fetchPlaylistsFromServer() async -> Result<String, ServerError> {
        let server = CreatureServerClient.shared

        logger.info("attempting to fetch the playlists")
        let fetchResult = await server.getAllPlaylists()
        switch fetchResult {
        case .success(let playlistList):
            logger.debug("pulled \(playlistList.count) playlists from the server")
            self.reload(with: playlistList)
            return .success("Successfully loaded \(playlistList.count) playlists")
        case .failure(let error):
            logger.warning("Unable to fetch the list of playlists from the server: \(error)")
            await AppState.shared.setSystemAlert(show: true, message: error.localizedDescription)
            return .failure(error)
        }
    }
}
