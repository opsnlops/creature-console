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

    private var continuations: [UUID: AsyncStream<PlaylistCacheState>.Continuation] = [:]

    var stateUpdates: AsyncStream<PlaylistCacheState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private init() {}

    private func currentSnapshot() -> PlaylistCacheState {
        PlaylistCacheState(
            playlists: playlists,
            empty: empty
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<PlaylistCacheState>.Continuation) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    func addPlaylist(_ playlist: Playlist, for id: PlaylistIdentifier) {
        playlists[id] = playlist
        empty = playlists.isEmpty
        publishState()
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        logger.debug("PlaylistCache: Broadcasting state (count: \(self.playlists.count), empty: \(self.empty))")
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
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
