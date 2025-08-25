import Combine
import Common
import Foundation
import OSLog

struct SoundListCacheState: Sendable {
    let sounds: [SoundIdentifier: Sound]
    let empty: Bool
}

actor SoundListCache {
    static let shared = SoundListCache()

    private var sounds: [SoundIdentifier: Sound] = [:]
    private var empty: Bool = true
    private var loadCacheTask: Task<Void, Never>? = nil

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "SoundListCache")

    // AsyncStream for UI updates
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(
        of: SoundListCacheState.self)

    var stateUpdates: AsyncStream<SoundListCacheState> {
        stateStream
    }

    private init() {}

    func addSound(_ sound: Sound, for id: SoundIdentifier) {
        sounds[id] = sound
        empty = sounds.isEmpty
        publishState()
    }

    private func publishState() {
        let currentState = SoundListCacheState(
            sounds: sounds,
            empty: empty
        )
        stateContinuation.yield(currentState)
    }

    func removeSound(for id: SoundIdentifier) {
        sounds.removeValue(forKey: id)
        empty = sounds.isEmpty
        publishState()
    }

    public func reload(with sounds: [Sound]) {
        let reloadedSounds = Dictionary(uniqueKeysWithValues: sounds.map { ($0.id, $0) })
        self.sounds = reloadedSounds
        self.empty = reloadedSounds.isEmpty
        publishState()
    }

    public func getById(id: SoundIdentifier) -> Result<Sound, ServerError> {
        if let sound = sounds[id] {
            return .success(sound)
        } else {
            logger.warning(
                "SoundListCache.getById() called on an ID that wasn't in the cache! \(id)")
            return .failure(.notFound("Sound ID \(id) not found in the cache"))
        }
    }

    public func fetchSoundsFromServer() async -> Result<String, ServerError> {
        let server = CreatureServerClient.shared

        // If there's one in flight, stop it
        loadCacheTask?.cancel()

        logger.info("attempting to fetch the sounds")
        let fetchResult = await server.listSounds()
        switch fetchResult {
        case .success(let soundList):
            logger.debug("pulled \(soundList.count) sounds from the server")
            self.reload(with: soundList)
            return .success("Successfully loaded \(soundList.count) sounds")
        case .failure(let error):
            logger.warning("Unable to fetch the list of sounds from the server: \(error)")
            await AppState.shared.setSystemAlert(show: true, message: error.localizedDescription)
            return .failure(error)
        }
    }
}
