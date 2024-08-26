import Combine
import Common
import Foundation
import OSLog

class PlaylistCache: ObservableObject {
    static let shared = PlaylistCache()

    @Published public private(set) var playlists: [PlaylistIdentifier: Playlist] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistCache")
    private let queue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.PlaylistCache.queue", attributes: .concurrent)

    private init() {}

    func addPlaylist(_ playlist: Playlist, for id: PlaylistIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.playlists[id] = playlist
                self.empty = self.playlists.isEmpty
            }
        }
    }

    func removePlaylist(for id: PlaylistIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.playlists.removeValue(forKey: id)
                self.empty = self.playlists.isEmpty
            }
        }
    }

    public func reload(with playlists: [Playlist]) {
        queue.async(flags: .barrier) {
            let realoadPlaylists = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
            DispatchQueue.main.async {
                self.playlists = realoadPlaylists
                self.empty = realoadPlaylists.isEmpty
            }
        }
    }

    public func getById(id: PlaylistIdentifier) -> Result<Playlist, ServerError> {
        queue.sync {
            if let playlist = playlists[id] {
                return .success(playlist)
            } else {
                logger.warning("PlaylistCache.getById() called on an ID that wasn't in the cache! \(id)")
                return .failure(.notFound("Playlist ID \(id) not found in the cache"))
            }
        }
    }

    public func fetchPlaylistsFromServer() -> Result<String, ServerError> {
        let server = CreatureServerClient.shared

        Task {

            #warning("Remove this delay after figuring out the server concurrency issues")
            try await Task.sleep(nanoseconds: 1_000_000_000)

            logger.info("attempting to fetch the playlists")
            let fetchResult = await server.getAllPlaylists()
            switch fetchResult {
                case .success(let playlistList):
                    logger.debug("pulled \(playlistList.count) playlists from the server")
                    self.reload(with: playlistList)
                case .failure(let error):
                    logger.warning("Unable to fetch the list of playlists from the server")
                    DispatchQueue.main.async {
                        AppState.shared.systemAlertMessage = error.localizedDescription
                        AppState.shared.showSystemAlert = true
                    }
            }
        }
        return .success("done")
    }
}

