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

    private var continuations: [UUID: AsyncStream<SoundListCacheState>.Continuation] = [:]

    var stateUpdates: AsyncStream<SoundListCacheState> {
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

    func addSound(_ sound: Sound, for id: SoundIdentifier) {
        sounds[id] = sound
        empty = sounds.isEmpty
        publishState()
    }

    private func currentSnapshot() -> SoundListCacheState {
        SoundListCacheState(
            sounds: sounds,
            empty: empty
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<SoundListCacheState>.Continuation) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        logger.debug("SoundListCache: Broadcasting state (count: \(self.sounds.count), empty: \(self.empty))")
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
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
            await AppState.shared.setSystemAlert(
                show: true, message: error.localizedDescription)
            return .failure(error)
        }
    }

    public func getCurrentState() -> SoundListCacheState {
        return SoundListCacheState(sounds: sounds, empty: empty)
    }
}

