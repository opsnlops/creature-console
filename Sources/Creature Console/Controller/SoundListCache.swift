import Combine
import Common
import Foundation
import OSLog

class SoundListCache: ObservableObject {
    static let shared = SoundListCache()

    @Published public private(set) var sounds: [SoundIdentifier: Sound] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "SoundListCache")
    private let queue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.SoundListCache.queue", attributes: .concurrent)

    private init() {}

    func addSound(_ sound: Sound, for id: PlaylistIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.sounds[id] = sound
                self.empty = self.sounds.isEmpty
            }
        }
    }

    func removeSound(for id: SoundIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.sounds.removeValue(forKey: id)
                self.empty = self.sounds.isEmpty
            }
        }
    }

    public func reload(with sounds: [Sound]) {
        queue.async(flags: .barrier) {
            let reloadSounds = Dictionary(uniqueKeysWithValues: sounds.map { ($0.id, $0) })
            DispatchQueue.main.async {
                self.sounds = reloadSounds
                self.empty = reloadSounds.isEmpty
            }
        }
    }

    public func getById(id: SoundIdentifier) -> Result<Sound, ServerError> {
        queue.sync {
            if let sound = sounds[id] {
                return .success(sound)
            } else {
                logger.warning("SoundIdentifier.getById() called on an ID that wasn't in the cache! \(id)")
                return .failure(.notFound("Sound ID \(id) not found in the cache"))
            }
        }
    }

    public func fetchSoundsFromServer() -> Result<String, ServerError> {
        let server = CreatureServerClient.shared

        Task {

            logger.info("attempting to fetch the sounds")
            let fetchResult = await server.listSounds()
            switch fetchResult {
                case .success(let soundList):
                    logger.debug("pulled \(soundList.count) sounds from the server")
                    self.reload(with: soundList)
                case .failure(let error):
                    logger.warning("Unable to fetch the list of sounds from the server")
                    DispatchQueue.main.async {
                        AppState.shared.systemAlertMessage = error.localizedDescription
                        AppState.shared.showSystemAlert = true
                    }
            }
        }
        return .success("done")
    }
}


